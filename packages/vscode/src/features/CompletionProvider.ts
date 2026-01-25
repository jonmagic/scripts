// CompletionProvider for wikilink autocompletion.
// Triggers on [[ and provides a list of files to link to.
// Shows 10 most recently modified files first, then all files filtered by input.
// Inserts full path-based links: [[Full/Path/To/File]]

import * as vscode from "vscode"
import * as fs from "node:fs"
import { pathToDisplayPath } from "@jonmagic/scripts-core"
import { getWorkspaceCache, type CachedFile } from "../cache/workspaceCache"

export class WikilinkCompletionProvider implements vscode.CompletionItemProvider {
  provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position
  ): vscode.ProviderResult<vscode.CompletionItem[] | vscode.CompletionList> {
    // Check if we're inside a wikilink (after [[)
    const linePrefix = document.lineAt(position).text.substring(0, position.character)

    // Find the last [[ that isn't closed
    const lastOpenBracket = linePrefix.lastIndexOf("[[")
    if (lastOpenBracket === -1) {
      return undefined
    }

    // Check there's no ]] between [[ and cursor
    const afterBracket = linePrefix.substring(lastOpenBracket + 2)
    if (afterBracket.includes("]]")) {
      return undefined
    }

    // Get what the user has typed after [[
    const typedText = afterBracket.toLowerCase()

    const cache = getWorkspaceCache()
    if (!cache.isReady()) {
      return undefined
    }

    const allFiles = cache.getAllFiles()
    const items: vscode.CompletionItem[] = []

    // Get recent files for MRU ordering
    const recentFiles = cache.getRecentFiles(10)
    const recentPaths = new Set(recentFiles.map((f) => f.relativePath))

    // Sort files: recent first, then alphabetically
    const sortedFiles = [...allFiles].sort((a, b) => {
      const aIsRecent = recentPaths.has(a.relativePath)
      const bIsRecent = recentPaths.has(b.relativePath)

      if (aIsRecent && !bIsRecent) return -1
      if (!aIsRecent && bIsRecent) return 1

      // Both recent or both not - sort by mtime for recent, alpha for rest
      if (aIsRecent && bIsRecent) {
        return b.mtime - a.mtime
      }

      return a.relativePath.localeCompare(b.relativePath)
    })

    for (let i = 0; i < sortedFiles.length; i++) {
      const file = sortedFiles[i]
      if (!file) continue

      const displayPath = pathToDisplayPath(file.relativePath)

      // Filter by typed text if any
      if (typedText && !displayPath.toLowerCase().includes(typedText)) {
        continue
      }

      const item = new vscode.CompletionItem(
        displayPath,
        vscode.CompletionItemKind.File
      )

      // Calculate the range to replace - from [[ to cursor, plus any trailing ]]
      const lineText = document.lineAt(position.line).text
      const replaceStart = new vscode.Position(
        position.line,
        linePrefix.lastIndexOf("[[")
      )

      // Check if there's ]] after the cursor
      const afterCursor = lineText.substring(position.character)
      const hasClosingBrackets = afterCursor.startsWith("]]")
      const replaceEnd = hasClosingBrackets
        ? new vscode.Position(position.line, position.character + 2)
        : position

      const replaceRange = new vscode.Range(replaceStart, replaceEnd)

      // Insert full path-based wikilink (no UID prefix)
      item.insertText = `[[${displayPath}]]`
      item.range = replaceRange

      // Sort text: pad with zeros to maintain order
      // Recent files get 0-prefixed numbers, others get 1-prefixed
      const isRecent = recentPaths.has(file.relativePath)
      const sortPrefix = isRecent ? "0" : "1"
      item.sortText = `${sortPrefix}${String(i).padStart(6, "0")}`

      // Filter text: match on path
      item.filterText = `[[${displayPath}`

      // Documentation will be filled in by resolveCompletionItem (leave unset)

      // Store file info for resolution
      ;(item as CompletionItemWithFile).cachedFile = file

      items.push(item)
    }

    return items
  }

  async resolveCompletionItem(
    item: vscode.CompletionItem
  ): Promise<vscode.CompletionItem> {
    const file = (item as CompletionItemWithFile).cachedFile
    if (!file) return item

    try {
      // Read file content for preview
      const content = fs.readFileSync(file.absolutePath, "utf-8")

      // Limit preview to first ~500 chars
      const preview = content.slice(0, 500)
      const truncated = content.length > 500 ? preview + "\n\n..." : preview

      item.documentation = new vscode.MarkdownString(truncated)
    } catch {
      // File might have been deleted
    }

    return item
  }
}

interface CompletionItemWithFile extends vscode.CompletionItem {
  cachedFile?: CachedFile
}
