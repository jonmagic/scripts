// Workspace cache for markdown files and UID index.
// Maintains an in-memory index of all markdown files and their UIDs
// for fast wikilink resolution and completion.
// Also tracks backlinks (which files link to which) for rename support.
//
// Two-phase initialization:
// 1. initializeFast() - Quick load of Meeting Notes folders + recent files (7 days)
// 2. initializeFull() - Background load of all files for complete index

import * as vscode from "vscode"
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

export interface CachedFile {
  /** Absolute path to the file */
  absolutePath: string
  /** Relative path from workspace root */
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
  private workspaceRoot: string | null = null
  private fileWatcher: vscode.FileSystemWatcher | null = null
  private isInitialized = false
  private isFullyLoaded = false

  /**
   * Fast initialization - only loads Meeting Notes folders and recent files.
   * Call this during extension activation for quick startup.
   */
  async initializeFast(): Promise<void> {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0]
    if (!workspaceFolder) {
      return
    }

    this.workspaceRoot = workspaceFolder.uri.fsPath

    // Load Meeting Notes folder names (for {{pending}} completion)
    await this.loadMeetingNotesFolders()

    // Load only files modified in the last 7 days
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000
    const mdFiles = await vscode.workspace.findFiles("**/*.md", "**/node_modules/**")

    for (const uri of mdFiles) {
      try {
        const stat = await fs.stat(uri.fsPath)
        if (stat.mtimeMs >= sevenDaysAgo) {
          await this.addFileAsync(uri.fsPath)
        }
      } catch {
        // File might have been deleted
      }
    }

    // Rebuild indices with what we have
    this.rebuildUidIndex()
    this.rebuildBacklinks()

    // Set up file watcher
    this.fileWatcher = vscode.workspace.createFileSystemWatcher("**/*.md")
    this.fileWatcher.onDidCreate((uri) => void this.onFileCreated(uri))
    this.fileWatcher.onDidChange((uri) => void this.onFileChanged(uri))
    this.fileWatcher.onDidDelete((uri) => this.onFileDeleted(uri))

    this.isInitialized = true
  }

  /**
   * Full initialization - loads all markdown files.
   * Call this in background after fast init for complete index.
   */
  async initializeFull(): Promise<void> {
    if (!this.workspaceRoot) {
      return
    }

    // Find all markdown files not already cached
    const mdFiles = await vscode.workspace.findFiles("**/*.md", "**/node_modules/**")

    for (const uri of mdFiles) {
      if (!this.files.has(uri.fsPath)) {
        await this.addFileAsync(uri.fsPath)
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
    if (!this.workspaceRoot) return

    const meetingNotesPath = path.join(this.workspaceRoot, "Meeting Notes")
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
    this.files.clear()
    this.uidIndex = { byUid: new Map(), byPath: new Map() }
    this.backlinks.clear()
    this.meetingNotesFolders.clear()
    this.isInitialized = false
    this.isFullyLoaded = false
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
   * Get workspace root path.
   */
  getWorkspaceRoot(): string | null {
    return this.workspaceRoot
  }

  // Private methods

  private async addFileAsync(absolutePath: string): Promise<void> {
    if (!this.workspaceRoot) return

    try {
      const stat = await fs.stat(absolutePath)
      const content = await fs.readFile(absolutePath, "utf-8")
      const relativePath = path.relative(this.workspaceRoot, absolutePath)
      const uid = extractUid(content)

      // Extract outgoing links
      const links = extractWikilinks(content)
      const outgoingLinks = links.map((link) => {
        // Handle uid: prefix links by extracting the path from label
        if (link.isUid && link.label) {
          return link.label.replace(/\.md$/, "")
        }
        return link.target.replace(/\.md$/, "")
      })

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
    await this.addFileAsync(uri.fsPath)
    this.rebuildUidIndex()
    this.rebuildBacklinks()
  }

  private async onFileChanged(uri: vscode.Uri): Promise<void> {
    await this.addFileAsync(uri.fsPath)
    this.rebuildUidIndex()
    this.rebuildBacklinks()
  }

  private onFileDeleted(uri: vscode.Uri): void {
    this.files.delete(uri.fsPath)
    this.rebuildUidIndex()
    this.rebuildBacklinks()
  }
}

// Singleton instance
let cacheInstance: WorkspaceCache | null = null

/**
 * Get the global workspace cache instance.
 */
export function getWorkspaceCache(): WorkspaceCache {
  if (!cacheInstance) {
    cacheInstance = new WorkspaceCache()
  }
  return cacheInstance
}

/**
 * Dispose of the global cache instance.
 */
export function disposeWorkspaceCache(): void {
  cacheInstance?.dispose()
  cacheInstance = null
}
