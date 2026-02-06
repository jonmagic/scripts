// Command to add frontmatter to the current file and update all links to it.
// After adding frontmatter with a UID, scans the workspace for path-based links
// pointing to this file and rewrites them to UID format.

import * as vscode from "vscode"
import * as fs from "node:fs"
import * as path from "node:path"
import {
  generateTid,
  hasFrontmatter,
  serializeFrontmatter,
  extractWikilinks,
  pathToDisplayPath,
  formatWikilink,
  type FrontmatterData,
} from "@jonmagic/scripts-core"
import { getWorkspaceCache } from "../cache/workspaceCache"

// Collection type detection based on file path
const COLLECTION_PATTERNS: Array<{ type: string; pattern: RegExp }> = [
  { type: "daily.project", pattern: /Daily Projects\/\d{4}-\d{2}-\d{2}\// },
  { type: "weekly.note", pattern: /Weekly Notes\/Week of \d{4}-\d{2}-\d{2}\.md$/ },
  { type: "meeting.note", pattern: /Meeting Notes\// },
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
  const workspaceRoot = cache.getWorkspaceRoot()
  if (!workspaceRoot) {
    vscode.window.showErrorMessage("No workspace folder open")
    return
  }

  const content = document.getText()

  // Check if already has frontmatter
  if (hasFrontmatter(content)) {
    vscode.window.showInformationMessage("File already has frontmatter")
    return
  }

  const absolutePath = document.uri.fsPath
  const relativePath = path.relative(workspaceRoot, absolutePath)

  // Detect collection type
  const type = detectCollectionType(relativePath)

  // Detect created date (from path or file mtime)
  const pathDate = extractDateFromPath(relativePath)
  const stat = fs.statSync(absolutePath)
  const createdDate = pathDate ?? stat.mtime

  // Generate TID
  const uid = generateTid(createdDate)

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
  const linksUpdated = updateLinksToFile(workspaceRoot, relativePath, displayPath, uid)

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
  workspaceRoot: string,
  targetRelativePath: string,
  displayPath: string,
  uid: string
): number {
  const cache = getWorkspaceCache()
  const allFiles = cache.getAllFiles()
  let totalUpdated = 0

  // Possible paths that might be used to link to this file
  const possibleTargets = [
    targetRelativePath,
    displayPath,
    path.basename(displayPath), // short ref
    path.basename(targetRelativePath),
  ].map((p) => p.toLowerCase())

  for (const file of allFiles) {
    // Skip the target file itself
    if (file.relativePath === targetRelativePath) {
      continue
    }

    const absolutePath = path.join(workspaceRoot, file.relativePath)
    let content: string
    try {
      content = fs.readFileSync(absolutePath, "utf-8")
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
      fs.writeFileSync(absolutePath, newContent, "utf-8")
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
