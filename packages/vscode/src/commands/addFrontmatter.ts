// Command to add frontmatter to the current file and update all links to it.
// After adding frontmatter with a UID, scans the workspace for path-based links
// pointing to this file and rewrites them to UID format.

import * as vscode from "vscode"
import * as fs from "node:fs"
import * as path from "node:path"
import {
  generateUniqueTid,
  hasFrontmatter,
  serializeFrontmatter,
  extractWikilinks,
  pathToDisplayPath,
  formatWikilink,
  type FrontmatterData,
} from "@jonmagic/scripts-core"
import { getWorkspaceCache } from "../cache/workspaceCache"
import { getBrainPath, getRelativeBrainPath } from "../config/brainPath"

// Collection type detection based on file path
const COLLECTION_PATTERNS: Array<{ type: string; pattern: RegExp }> = [
  { type: "daily.project", pattern: /Daily Projects\/\d{4}-\d{2}-\d{2}\// },
  { type: "weekly.note", pattern: /Weekly Notes\/Week of \d{4}-\d{2}-\d{2}\.md$/ },
  { type: "meeting.note", pattern: /Meeting Notes\// },
  { type: "bookmark", pattern: /Bookmarks\/\d{4}-\d{2}-\d{2}\// },
  { type: "project", pattern: /Projects\// },
  { type: "snippet", pattern: /Snippets\// },
  { type: "transcript", pattern: /Transcripts\/\d{4}-\d{2}-\d{2}\// },
  { type: "executive.summary", pattern: /Executive Summaries\/\d{4}-\d{2}-\d{2}\// },
  { type: "archive", pattern: /Archive\// },
]

function detectCollectionType(relativePath: string): string {
  for (const { type, pattern } of COLLECTION_PATTERNS) {
    if (pattern.test(relativePath)) {
      return type
    }
  }
  return "unknown"
}

function extractDateFromPath(filePath: string): Date | null {
  // Match YYYY-MM-DD anywhere in path
  const match = filePath.match(/(\d{4}-\d{2}-\d{2})/)
  if (match?.[1]) {
    return new Date(match[1] + "T00:00:00")
  }
  return null
}

export async function addFrontmatter(): Promise<void> {
  const editor = vscode.window.activeTextEditor
  if (!editor) {
    vscode.window.showWarningMessage("No active editor")
    return
  }

  const document = editor.document
  if (document.languageId !== "markdown") {
    vscode.window.showWarningMessage("Current file is not a markdown file")
    return
  }

  const cache = getWorkspaceCache()
  const brainRoot = getBrainPath()
  const relativePath = getRelativeBrainPath(document.uri.fsPath, brainRoot)
  if (!relativePath) {
    vscode.window.showErrorMessage(
      `Current file is outside the configured Brain folder: ${brainRoot}`
    )
    return
  }

  const content = document.getText()

  // Check if already has frontmatter
  if (hasFrontmatter(content)) {
    vscode.window.showInformationMessage("File already has frontmatter")
    return
  }

  const absolutePath = document.uri.fsPath
  if (!cache.hasFullIndex()) {
    await cache.refresh()
  }

  // Detect collection type
  const type = detectCollectionType(relativePath)

  // Detect created date (from path or file mtime)
  const pathDate = extractDateFromPath(relativePath)
  const stat = fs.statSync(absolutePath)
  const createdDate = pathDate ?? stat.mtime

  // Generate TID
  const uid = generateUniqueTid(
    cache.getUidIndex().byUid.keys(),
    createdDate,
    relativePath
  )

  // Build frontmatter
  const frontmatterData: FrontmatterData = {
    uid,
    type,
    created: createdDate.toISOString(),
  }

  const frontmatterText = serializeFrontmatter(frontmatterData)

  // Add frontmatter to document
  await editor.edit((editBuilder) => {
    editBuilder.insert(new vscode.Position(0, 0), frontmatterText + "\n\n")
  })

  // Save the document
  await document.save()

  // Refresh cache to pick up the new UID
  await cache.refresh()

  // Now find and update all links pointing to this file
  const displayPath = pathToDisplayPath(relativePath)
  const linksUpdated = updateLinksToFile(relativePath, displayPath, uid)

  if (linksUpdated > 0) {
    await cache.refresh()
  }

  if (linksUpdated > 0) {
    vscode.window.showInformationMessage(
      `Added frontmatter with UID ${uid}. Updated ${linksUpdated} link(s) in other files.`
    )
  } else {
    vscode.window.showInformationMessage(
      `Added frontmatter with UID ${uid}.`
    )
  }
}

function updateLinksToFile(
  targetRelativePath: string,
  displayPath: string,
  uid: string
): number {
  const cache = getWorkspaceCache()
  const allFiles = cache.getAllFiles()
  let totalUpdated = 0

  // Possible paths that might be used to link to this file
  const possibleTargets = Array.from(
    new Set(
      [
        targetRelativePath,
        displayPath,
        path.posix.basename(displayPath), // short ref
        path.posix.basename(targetRelativePath),
      ].map((candidate) => candidate.toLowerCase())
    )
  )

  for (const file of allFiles) {
    // Skip the target file itself
    if (file.relativePath === targetRelativePath) {
      continue
    }

    let content: string
    try {
      content = fs.readFileSync(file.absolutePath, "utf-8")
    } catch {
      continue
    }

    const links = extractWikilinks(content)
    let modified = false
    let newContent = content

    for (const link of links) {
      // Skip if already a UID link
      if (link.isUid) {
        continue
      }

      // Check if this link points to our target file
      const linkTarget = link.target.toLowerCase()
      const isMatch = possibleTargets.some(
        (t) => linkTarget === t || linkTarget === t.replace(/\.md$/, "")
      )

      if (isMatch) {
        // Replace this link with UID format
        const newLink = formatWikilink(uid, displayPath)
        newContent = newContent.replace(link.full, newLink)
        modified = true
        totalUpdated++
      }
    }

    if (modified) {
      fs.writeFileSync(file.absolutePath, newContent, "utf-8")
    }
  }

  return totalUpdated
}

export function registerAddFrontmatterCommand(
  context: vscode.ExtensionContext
): void {
  const disposable = vscode.commands.registerCommand(
    "jonmagic.addFrontmatter",
    addFrontmatter
  )
  context.subscriptions.push(disposable)
}
