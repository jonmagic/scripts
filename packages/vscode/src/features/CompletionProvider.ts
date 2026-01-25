// CompletionProvider for wikilink autocompletion.
// Triggers on [[ and provides a list of files to link to.
// Also triggers on {{ for pending meeting placeholders.
// Shows 10 most recently modified files first, then all files filtered by input.
// Inserts full path-based links: [[Full/Path/To/File]] or {{Meeting Notes/Target}}

import * as vscode from "vscode"
import * as fs from "node:fs"
import { pathToDisplayPath } from "@jonmagic/scripts-core"
import { getWorkspaceCache, type CachedFile } from "../cache/workspaceCache"

type LinkStyle = "wikilink" | "pending"

export class WikilinkCompletionProvider implements vscode.CompletionItemProvider {
  provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position
  ): vscode.ProviderResult<vscode.CompletionItem[] | vscode.CompletionList> {
    const linePrefix = document.lineAt(position).text.substring(0, position.character)

    // Determine if we're in a wikilink [[ or pending placeholder {{
    let linkStyle: LinkStyle | null = null
    let openIndex = -1
    let typedText = ""

    // Check for pending placeholder {{ first (more specific)
    const lastOpenBrace = linePrefix.lastIndexOf("{{")
    if (lastOpenBrace !== -1) {
      const afterBrace = linePrefix.substring(lastOpenBrace + 2)
      if (!afterBrace.includes("}}")) {
        linkStyle = "pending"
        openIndex = lastOpenBrace
        typedText = afterBrace.toLowerCase()
      }
    }

    // Check for wikilink [[
    if (!linkStyle) {
      const lastOpenBracket = linePrefix.lastIndexOf("[[")
      if (lastOpenBracket !== -1) {
        const afterBracket = linePrefix.substring(lastOpenBracket + 2)
        if (!afterBracket.includes("]]")) {
          linkStyle = "wikilink"
          openIndex = lastOpenBracket
          typedText = afterBracket.toLowerCase()
        }
      }
    }

    if (!linkStyle || openIndex === -1) {
      return undefined
    }

    const cache = getWorkspaceCache()
    if (!cache.isReady()) {
      return undefined
    }

    const allFiles = cache.getAllFiles()
    const items: vscode.CompletionItem[] = []

    // For pending placeholders, only show Meeting Notes targets
    const isPending = linkStyle === "pending"

    // Get recent files for MRU ordering
    const recentFiles = cache.getRecentFiles(10)
    const recentPaths = new Set(recentFiles.map((f) => f.relativePath))

    // For pending placeholders, extract unique Meeting Notes targets
    if (isPending) {
      const meetingTargets = new Set<string>()

      for (const file of allFiles) {
        // Match Meeting Notes/<target>/... paths
        const match = file.relativePath.match(/^Meeting Notes\/([^/]+)\//)
        if (match) {
          meetingTargets.add(match[1]!)
        }
      }

      const sortedTargets = Array.from(meetingTargets).sort()

      for (let i = 0; i < sortedTargets.length; i++) {
        const target = sortedTargets[i]!
        const displayPath = `Meeting Notes/${target}`

        // Filter by typed text
        if (typedText && !displayPath.toLowerCase().includes(typedText)) {
          continue
        }

        const item = new vscode.CompletionItem(
          displayPath,
          vscode.CompletionItemKind.Reference
        )

        // Calculate replace range
        const lineText = document.lineAt(position.line).text
        const replaceStart = new vscode.Position(position.line, openIndex)
        const afterCursor = lineText.substring(position.character)
        const hasClosing = afterCursor.startsWith("}}")
        const replaceEnd = hasClosing
          ? new vscode.Position(position.line, position.character + 2)
          : position

        item.insertText = `{{${displayPath}}}`
        item.range = new vscode.Range(replaceStart, replaceEnd)
        item.sortText = String(i).padStart(6, "0")
        item.filterText = `{{${displayPath}`
        item.detail = "Pending meeting placeholder"

        items.push(item)
      }

      return items
    }

    // Standard wikilink completion
    const sortedFiles = [...allFiles].sort((a, b) => {
      const aIsRecent = recentPaths.has(a.relativePath)
      const bIsRecent = recentPaths.has(b.relativePath)

      if (aIsRecent && !bIsRecent) return -1
      if (!aIsRecent && bIsRecent) return 1

      if (aIsRecent && bIsRecent) {
        return b.mtime - a.mtime
      }

      return a.relativePath.localeCompare(b.relativePath)
    })

    for (let i = 0; i < sortedFiles.length; i++) {
      const file = sortedFiles[i]
      if (!file) continue

      const displayPath = pathToDisplayPath(file.relativePath)

      if (typedText && !displayPath.toLowerCase().includes(typedText)) {
        continue
      }

      const item = new vscode.CompletionItem(
        displayPath,
        vscode.CompletionItemKind.File
      )

      const lineText = document.lineAt(position.line).text
      const replaceStart = new vscode.Position(position.line, openIndex)
      const afterCursor = lineText.substring(position.character)
      const hasClosingBrackets = afterCursor.startsWith("]]")
      const replaceEnd = hasClosingBrackets
        ? new vscode.Position(position.line, position.character + 2)
        : position

      const replaceRange = new vscode.Range(replaceStart, replaceEnd)

      item.insertText = `[[${displayPath}]]`
      item.range = replaceRange

      const isRecent = recentPaths.has(file.relativePath)
      const sortPrefix = isRecent ? "0" : "1"
      item.sortText = `${sortPrefix}${String(i).padStart(6, "0")}`
      item.filterText = `[[${displayPath}`

      ;(item as CompletionItemWithFile).cachedFile = file

      items.push(item)
    }

    return items
  }

  resolveCompletionItem(
    item: vscode.CompletionItem
  ): vscode.CompletionItem {
    const file = (item as CompletionItemWithFile).cachedFile
    if (!file) return item

    try {
      const content = fs.readFileSync(file.absolutePath, "utf-8")
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
