// Workspace cache for markdown files and UID index.
// Maintains an in-memory index of all markdown files and their UIDs
// for fast wikilink resolution and completion.
// Also tracks backlinks (which files link to which) for rename support.
//
// Two-phase initialization for cache-dependent Markdown features:
// 1. initializeFast() - Quick load of Meeting Notes folders + recent files (7 days)
// 2. initializeFull() - Load all files for complete wikilink/backlink resolution

import * as vscode from "vscode"
import type { Dirent } from "node:fs"
import * as fs from "node:fs/promises"
import * as path from "node:path"
import {
  buildUidIndex,
  type UidIndex,
  type FileInfo,
  extractUid,
  extractWikilinks,
  pathToDisplayPath,
} from "@jonmagic/scripts-core"
import {
  getBrainPath,
  getBrainRootUri,
  getRelativeBrainPath,
} from "../config/brainPath"
import { GitignoreMatcher } from "./gitignore"

export interface CachedFile {
  /** Absolute path to the file */
  absolutePath: string
  /** Relative path from Brain root */
  relativePath: string
  /** File modification time */
  mtime: number
  /** UID from frontmatter (if present) */
  uid: string | null
  /** Wikilink targets this file contains (relative paths without .md) */
  outgoingLinks: string[]
}

export class WorkspaceCache {
  private files: Map<string, CachedFile> = new Map()
  private uidIndex: UidIndex = { byUid: new Map(), byPath: new Map() }
  /** Backlinks index: target path → Set of files that link to it */
  private backlinks: Map<string, Set<string>> = new Map()
  /** Meeting Notes folder names for {{pending}} completion */
  private meetingNotesFolders: Set<string> = new Set()
  private brainRoot: string | null = null
  private fileWatcher: vscode.FileSystemWatcher | null = null
  private gitignoreWatcher: vscode.FileSystemWatcher | null = null
  private ignoreMatcher: GitignoreMatcher | null = null
  private isInitialized = false
  private isFullyLoaded = false

  /**
   * Fast initialization - only loads Meeting Notes folders and recent files.
   * Keep this out of sidebar-only activation paths.
   */
  async initializeFast(): Promise<void> {
    this.fileWatcher?.dispose()
    this.fileWatcher = null
    this.gitignoreWatcher?.dispose()
    this.gitignoreWatcher = null
    this.brainRoot = getBrainPath()
    this.ignoreMatcher = new GitignoreMatcher(this.brainRoot)

    // Load Meeting Notes folder names (for {{pending}} completion)
    await this.loadMeetingNotesFolders()

    // Load only files modified in the last 7 days
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000
    const mdFiles = await this.findMarkdownFiles(sevenDaysAgo)

    for (const filePath of mdFiles) {
      await this.addFileAsync(filePath)
    }

    // Rebuild indices with what we have
    this.rebuildUidIndex()
    this.rebuildBacklinks()

    // Set up file watcher
    this.fileWatcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(getBrainRootUri(), "**/*.md")
    )
    this.fileWatcher.onDidCreate((uri) => void this.onFileCreated(uri))
    this.fileWatcher.onDidChange((uri) => void this.onFileChanged(uri))
    this.fileWatcher.onDidDelete((uri) => void this.onFileDeleted(uri))

    this.gitignoreWatcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(getBrainRootUri(), "**/.gitignore")
    )
    const refreshIgnoredFiles = () => void this.refresh()
    this.gitignoreWatcher.onDidCreate(refreshIgnoredFiles)
    this.gitignoreWatcher.onDidChange(refreshIgnoredFiles)
    this.gitignoreWatcher.onDidDelete(refreshIgnoredFiles)

    this.isInitialized = true
  }

  /**
   * Full initialization - loads all markdown files.
   * Call this only when cache-backed Markdown features need the complete index.
   */
  async initializeFull(): Promise<void> {
    if (!this.brainRoot) {
      return
    }

    // Find all markdown files not already cached
    const mdFiles = await this.findMarkdownFiles()

    for (const filePath of mdFiles) {
      if (!this.files.has(filePath)) {
        await this.addFileAsync(filePath)
      }
    }

    // Rebuild indices with complete data
    this.rebuildUidIndex()
    this.rebuildBacklinks()

    this.isFullyLoaded = true
  }

  /**
   * Load Meeting Notes folder names for {{pending}} placeholder completion.
   */
  private async loadMeetingNotesFolders(): Promise<void> {
    if (!this.brainRoot) return

    const meetingNotesPath = path.join(this.brainRoot, "Meeting Notes")
    try {
      const entries = await fs.readdir(meetingNotesPath, { withFileTypes: true })
      for (const entry of entries) {
        if (entry.isDirectory() && !entry.name.startsWith(".")) {
          this.meetingNotesFolders.add(entry.name)
        }
      }
    } catch {
      // Meeting Notes folder doesn't exist
    }
  }

  /**
   * Dispose of resources.
   */
  dispose(): void {
    this.fileWatcher?.dispose()
    this.gitignoreWatcher?.dispose()
  }

  /**
   * Get Meeting Notes folder names for {{pending}} completion.
   */
  getMeetingNotesFolders(): string[] {
    return Array.from(this.meetingNotesFolders).sort()
  }

  /**
   * Get the UID index for wikilink resolution.
   */
  getUidIndex(): UidIndex {
    return this.uidIndex
  }

  /**
   * Get all markdown file paths (relative).
   */
  getMarkdownFiles(): string[] {
    return Array.from(this.files.values()).map((f) => f.relativePath)
  }

  /**
   * Get all cached file info.
   */
  getAllFiles(): CachedFile[] {
    return Array.from(this.files.values())
  }

  /**
   * Get the N most recently modified files.
   */
  getRecentFiles(limit: number): CachedFile[] {
    const sorted = Array.from(this.files.values()).sort(
      (a, b) => b.mtime - a.mtime
    )
    return sorted.slice(0, limit)
  }

  /**
   * Get files that link to a given path.
   * @param targetPath Relative path without .md extension
   * @returns Array of relative paths of files that contain links to targetPath
   */
  getBacklinks(targetPath: string): string[] {
    const normalized = targetPath.replace(/\.md$/, "")
    const linkers = this.backlinks.get(normalized)
    return linkers ? Array.from(linkers) : []
  }

  /**
   * Force a full refresh of the cache.
   */
  async refresh(): Promise<void> {
    const refresh = queueCacheOperation(() => this.refreshInternal())
    cacheInitialization = refresh

    try {
      await refresh
    } finally {
      if (cacheInitialization === refresh) {
        cacheInitialization = null
      }
    }
  }

  private async refreshInternal(): Promise<void> {
    this.files.clear()
    this.uidIndex = { byUid: new Map(), byPath: new Map() }
    this.backlinks.clear()
    this.meetingNotesFolders.clear()
    this.isInitialized = false
    this.isFullyLoaded = false
    this.fileWatcher?.dispose()
    this.fileWatcher = null
    this.gitignoreWatcher?.dispose()
    this.gitignoreWatcher = null
    this.ignoreMatcher = null
    await this.initializeFast()
    await this.initializeFull()
  }

  /**
   * Check if cache is initialized (fast init complete).
   */
  isReady(): boolean {
    return this.isInitialized
  }

  /**
   * Check if full cache is loaded (all files indexed).
   */
  hasFullIndex(): boolean {
    return this.isFullyLoaded
  }

  /**
   * Get Brain root path.
   */
  getBrainRoot(): string | null {
    return this.brainRoot
  }

  async isIgnoredPath(
    absolutePath: string,
    options: { isDirectory?: boolean } = {}
  ): Promise<boolean> {
    return this.shouldIgnorePath(absolutePath, options.isDirectory ?? false)
  }

  // Private methods

  private async addFileAsync(absolutePath: string): Promise<void> {
    if (!this.brainRoot) return

    if (await this.shouldIgnorePath(absolutePath, false)) {
      this.files.delete(absolutePath)
      return
    }

    try {
      const stat = await fs.stat(absolutePath)
      const content = await fs.readFile(absolutePath, "utf-8")
      const relativePath = getRelativeBrainPath(absolutePath, this.brainRoot)
      if (!relativePath) {
        return
      }

      const uid = extractUid(content)

      // Extract outgoing links
      const links = extractWikilinks(content)
      const outgoingLinks = links
        .filter((link) => !link.isUid)
        .map((link) => link.target.replace(/\.md$/, ""))

      this.files.set(absolutePath, {
        absolutePath,
        relativePath,
        mtime: stat.mtimeMs,
        uid,
        outgoingLinks,
      })

      // Check if this is a new Meeting Notes folder
      const meetingMatch = relativePath.match(/^Meeting Notes\/([^/]+)\//)
      if (meetingMatch && meetingMatch[1]) {
        this.meetingNotesFolders.add(meetingMatch[1])
      }
    } catch {
      // File might have been deleted or is unreadable
    }
  }

  private async findMarkdownFiles(modifiedSince?: number): Promise<string[]> {
    if (!this.brainRoot) {
      return []
    }

    const files: string[] = []
    await this.walkDirectory(this.brainRoot, files, modifiedSince)
    return files
  }

  private async walkDirectory(
    currentPath: string,
    files: string[],
    modifiedSince?: number
  ): Promise<void> {
    let entries: Dirent[]
    try {
      entries = await fs.readdir(currentPath, { withFileTypes: true })
    } catch {
      return
    }

    for (const entry of entries) {
      if (entry.name.startsWith(".")) {
        continue
      }

      const fullPath = path.join(currentPath, entry.name)

      if (entry.isDirectory()) {
        if (await this.shouldIgnorePath(fullPath, true)) {
          continue
        }
        await this.walkDirectory(fullPath, files, modifiedSince)
        continue
      }

      if (!entry.isFile() || !entry.name.endsWith(".md")) {
        continue
      }

      if (await this.shouldIgnorePath(fullPath, false)) {
        continue
      }

      if (modifiedSince !== undefined) {
        try {
          const stat = await fs.stat(fullPath)
          if (stat.mtimeMs < modifiedSince) {
            continue
          }
        } catch {
          continue
        }
      }

      files.push(fullPath)
    }
  }

  private async shouldIgnorePath(
    absolutePath: string,
    isDirectory: boolean
  ): Promise<boolean> {
    if (!this.brainRoot || !this.ignoreMatcher) {
      return false
    }

    const relativePath = getRelativeBrainPath(absolutePath, this.brainRoot)
    if (!relativePath) {
      return true
    }

    if (relativePath.split("/").some((part) => part.startsWith("."))) {
      return true
    }

    return this.ignoreMatcher.isIgnored(absolutePath, { isDirectory })
  }

  private rebuildUidIndex(): void {
    const fileInfos: FileInfo[] = []

    for (const cached of this.files.values()) {
      if (cached.uid) {
        fileInfos.push({
          relativePath: cached.relativePath,
          content: `---\nuid: ${cached.uid}\n---\n`, // Minimal content with UID
        })
      }
    }

    this.uidIndex = buildUidIndex(fileInfos)
  }

  private rebuildBacklinks(): void {
    this.backlinks.clear()

    for (const cached of this.files.values()) {
      const sourcePathNoExt = pathToDisplayPath(cached.relativePath)

      for (const targetPath of cached.outgoingLinks) {
        // Normalize target path
        const normalizedTarget = targetPath.replace(/\.md$/, "")

        if (!this.backlinks.has(normalizedTarget)) {
          this.backlinks.set(normalizedTarget, new Set())
        }
        this.backlinks.get(normalizedTarget)!.add(sourcePathNoExt)
      }
    }
  }

  private async onFileCreated(uri: vscode.Uri): Promise<void> {
    if (await this.shouldIgnorePath(uri.fsPath, false)) {
      return
    }

    await this.addFileAsync(uri.fsPath)
    this.rebuildUidIndex()
    this.rebuildBacklinks()
  }

  private async onFileChanged(uri: vscode.Uri): Promise<void> {
    if (await this.shouldIgnorePath(uri.fsPath, false)) {
      this.files.delete(uri.fsPath)
      this.rebuildUidIndex()
      this.rebuildBacklinks()
      return
    }

    await this.addFileAsync(uri.fsPath)
    this.rebuildUidIndex()
    this.rebuildBacklinks()
  }

  private async onFileDeleted(uri: vscode.Uri): Promise<void> {
    if (await this.shouldIgnorePath(uri.fsPath, false)) {
      return
    }

    this.files.delete(uri.fsPath)
    this.rebuildUidIndex()
    this.rebuildBacklinks()
  }
}

// Singleton instance
let cacheInstance: WorkspaceCache | null = null
let cacheInitialization: Promise<void> | null = null
let cacheOperation: Promise<void> = Promise.resolve()

function queueCacheOperation(operation: () => Promise<void>): Promise<void> {
  const queued = cacheOperation.catch(() => undefined).then(operation)
  cacheOperation = queued.catch(() => undefined)
  return queued
}

/**
 * Get the global Brain cache instance.
 */
export function getWorkspaceCache(): WorkspaceCache {
  if (!cacheInstance) {
    cacheInstance = new WorkspaceCache()
  }
  return cacheInstance
}

export async function initializeWorkspaceCache(): Promise<void> {
  const cache = getWorkspaceCache()
  if (cache.hasFullIndex()) {
    return
  }

  if (!cacheInitialization) {
    const initialization = queueCacheOperation(async () => {
      if (cache.hasFullIndex()) {
        return
      }

      await cache.initializeFast()
      await cache.initializeFull()
    })
      .finally(() => {
        if (cacheInitialization === initialization) {
          cacheInitialization = null
        }
      })
    cacheInitialization = initialization
  }

  await cacheInitialization
}

export function startWorkspaceCacheInitialization(): void {
  void initializeWorkspaceCache().catch((error: unknown) => {
    console.error("Failed to initialize Brain workspace cache", error)
  })
}

/**
 * Dispose of the global cache instance.
 */
export function disposeWorkspaceCache(): void {
  cacheInstance?.dispose()
  cacheInstance = null
  cacheInitialization = null
  cacheOperation = Promise.resolve()
}
