import * as vscode from "vscode"

import { createDailyProjectNote } from "@jonmagic/scripts-core"
import { getWorkspaceCache, disposeWorkspaceCache } from "./cache/workspaceCache"
import { WikilinkDocumentLinkProvider } from "./features/DocumentLinkProvider"
import { WikilinkCompletionProvider } from "./features/CompletionProvider"
import { registerFileRenameHandler } from "./features/FileRenameHandler"
import { registerOpenDocumentCommand } from "./commands/openDocumentByReference"
import { registerAddFrontmatterCommand } from "./commands/addFrontmatter"

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  // Initialize workspace cache
  const cache = getWorkspaceCache()
  await cache.initialize()

  // Register document link provider for wikilinks
  const linkProvider = new WikilinkDocumentLinkProvider()
  context.subscriptions.push(
    vscode.languages.registerDocumentLinkProvider(
      { language: "markdown" },
      linkProvider
    )
  )

  // Register completion provider for wikilinks (triggers on [ and {)
  const completionProvider = new WikilinkCompletionProvider()
  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider(
      { language: "markdown" },
      completionProvider,
      "[", // Trigger on [ for [[wikilinks]]
      "{"  // Trigger on { for {{pending placeholders}}
    )
  )

  // Register file rename handler to auto-update wikilinks
  registerFileRenameHandler(context)

  // Register commands
  registerOpenDocumentCommand(context)
  registerAddFrontmatterCommand(context)

  // Register daily project note command
  const createNoteDisposable = vscode.commands.registerCommand(
    "jonmagic.scripts.createDailyProjectNote",
    async () => {
      const title = await vscode.window.showInputBox({
        title: "Create Daily Project Note",
        prompt: "Title for the new Daily Project note",
        placeHolder: "refactor stale queue cleanup"
      })

      if (!title?.trim()) {
        return
      }

      try {
        const result = await createDailyProjectNote({ title })
        const doc = await vscode.workspace.openTextDocument(
          vscode.Uri.file(result.filePath)
        )
        await vscode.window.showTextDocument(doc, { preview: false })
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        await vscode.window.showErrorMessage(message)
      }
    }
  )

  context.subscriptions.push(createNoteDisposable)
}

export function deactivate(): void {
  disposeWorkspaceCache()
}
