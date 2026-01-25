// File rename handler for automatic wikilink updates.
// When a markdown file is renamed/moved, updates all wikilinks
// that pointed to the old path.

import * as vscode from "vscode"
import * as fs from "node:fs"
import * as path from "node:path"
import { getWorkspaceCache } from "../cache/workspaceCache"
import { pathToDisplayPath } from "@jonmagic/scripts-core"

/**
 * Register the file rename handler.
 */
export function registerFileRenameHandler(
  context: vscode.ExtensionContext
): void {
  const disposable = vscode.workspace.onDidRenameFiles((event) => {
    for (const { oldUri, newUri } of event.files) {
      handleFileRename(oldUri, newUri)
    }
  })

  context.subscriptions.push(disposable)
}

/**
 * Handle a single file rename event.
 */
function handleFileRename(
  oldUri: vscode.Uri,
  newUri: vscode.Uri
): void {
  // Only process markdown files
  if (!oldUri.fsPath.endsWith(".md")) {
    return
  }

  const cache = getWorkspaceCache()
  const workspaceRoot = cache.getWorkspaceRoot()

  if (!workspaceRoot) {
    return
  }

  // Get paths without .md extension (how they appear in wikilinks)
  const oldRelativePath = path.relative(workspaceRoot, oldUri.fsPath)
  const newRelativePath = path.relative(workspaceRoot, newUri.fsPath)
  const oldDisplayPath = pathToDisplayPath(oldRelativePath)
  const newDisplayPath = pathToDisplayPath(newRelativePath)

  // Get all files that link to the old path
  const backlinks = cache.getBacklinks(oldDisplayPath)

  if (backlinks.length === 0) {
    return
  }

  let updatedCount = 0

  for (const linkingFilePath of backlinks) {
    // Convert display path back to relative path with .md
    const linkingAbsPath = path.join(workspaceRoot, linkingFilePath + ".md")

    // Skip if file doesn't exist (might have been renamed itself)
    if (!fs.existsSync(linkingAbsPath)) {
      continue
    }

    try {
      let content = fs.readFileSync(linkingAbsPath, "utf-8")
      const originalContent = content

      // Replace all wikilinks to the old path with the new path
      // Handle: [[old/path]], [[old/path|label]]
      const patterns = [
        // Exact match without label
        new RegExp(`\\[\\[${escapeRegExp(oldDisplayPath)}\\]\\]`, "g"),
        // With label
        new RegExp(`\\[\\[${escapeRegExp(oldDisplayPath)}\\|([^\\]]+)\\]\\]`, "g"),
      ] as const

      content = content.replace(patterns[0], `[[${newDisplayPath}]]`)
      content = content.replace(patterns[1], `[[${newDisplayPath}|$1]]`)

      if (content !== originalContent) {
        fs.writeFileSync(linkingAbsPath, content, "utf-8")
        updatedCount++
      }
    } catch (err) {
      console.error(`Failed to update links in ${linkingAbsPath}:`, err)
    }
  }

  if (updatedCount > 0) {
    vscode.window.showInformationMessage(
      `Updated ${updatedCount} wikilink${updatedCount === 1 ? "" : "s"} to renamed file`
    )
  }
}

/**
 * Escape special regex characters in a string.
 */
function escapeRegExp(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}
