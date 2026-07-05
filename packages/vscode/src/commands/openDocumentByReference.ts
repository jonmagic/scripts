// Command to open a document by wikilink reference.
// Handles both UID-based (uid:xxx) and path-based references.

import * as vscode from "vscode"
import * as path from "node:path"
import { resolveWikilink, UID_PREFIX } from "@jonmagic/scripts-core"
import {
  getWorkspaceCache,
  initializeWorkspaceCache,
} from "../cache/workspaceCache"
import { getBrainPath } from "../config/brainPath"

interface OpenDocumentArgs {
  reference: string
}

export async function openDocumentByReference(
  args: OpenDocumentArgs
): Promise<void> {
  const { reference } = args
  await initializeWorkspaceCache()
  const cache = getWorkspaceCache()
  const brainRoot = getBrainPath()

  // Resolve the reference to a path
  const uidIndex = cache.getUidIndex()
  const allPaths = cache.getMarkdownFiles()

  const resolvedPath = resolveWikilink(reference, uidIndex, allPaths)

  if (!resolvedPath) {
    // Link doesn't resolve - offer to create the file
    const isUid = reference.startsWith(UID_PREFIX)
    if (isUid) {
      vscode.window.showWarningMessage(
        `Could not find file with UID: ${reference.slice(UID_PREFIX.length)}`
      )
    } else {
      // Offer to create the file
      const create = await vscode.window.showWarningMessage(
        `File not found: ${reference}`,
        "Create File"
      )

      if (create === "Create File") {
        await createAndOpenFile(brainRoot, reference)
      }
    }
    return
  }

  // Open the resolved file
  const absolutePath = path.join(brainRoot, resolvedPath)
  try {
    const doc = await vscode.workspace.openTextDocument(absolutePath)
    await vscode.window.showTextDocument(doc)
  } catch {
    vscode.window.showErrorMessage(`Could not open file: ${resolvedPath}`)
  }
}

async function createAndOpenFile(
  brainRoot: string,
  reference: string
): Promise<void> {
  // Ensure reference has .md extension
  const filePath = reference.endsWith(".md") ? reference : `${reference}.md`
  const absolutePath = path.join(brainRoot, filePath)

  // Create the file with a basic header
  const title = path.basename(reference, ".md")
  const uri = vscode.Uri.file(absolutePath)

  // Create parent directories if needed
  await vscode.workspace.fs.createDirectory(vscode.Uri.file(path.dirname(absolutePath)))
  try {
    await vscode.workspace.fs.stat(uri)
  } catch {
    await vscode.workspace.fs.writeFile(uri, new Uint8Array())
  }

  // Write initial content
  const doc = await vscode.workspace.openTextDocument(uri)
  const editor = await vscode.window.showTextDocument(doc)

  if (doc.getText() === "") {
    await editor.edit((editBuilder) => {
      editBuilder.insert(new vscode.Position(0, 0), `# ${title}\n\n`)
    })
  }
}

export function registerOpenDocumentCommand(
  context: vscode.ExtensionContext
): void {
  const disposable = vscode.commands.registerCommand(
    "jonmagic.openDocumentByReference",
    openDocumentByReference
  )
  context.subscriptions.push(disposable)
}
