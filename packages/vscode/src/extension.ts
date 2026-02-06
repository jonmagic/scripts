import * as vscode from "vscode"

import { createDailyProjectNote } from "@jonmagic/scripts-core"
import { getWorkspaceCache, disposeWorkspaceCache } from "./cache/workspaceCache"
import { WikilinkDocumentLinkProvider } from "./features/DocumentLinkProvider"
import { WikilinkCompletionProvider } from "./features/CompletionProvider"
import { registerFileRenameHandler } from "./features/FileRenameHandler"
import { registerOpenDocumentCommand } from "./commands/openDocumentByReference"
import { registerAddFrontmatterCommand } from "./commands/addFrontmatter"
import { BrainSidebarProvider } from "./sidebar/BrainSidebarProvider"

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

  // Register Brain sidebar tree view
  const brainSidebarProvider = new BrainSidebarProvider()
  vscode.window.registerTreeDataProvider('brainWeekView', brainSidebarProvider)

  // Register Brain navigation commands
  context.subscriptions.push(
    vscode.commands.registerCommand('jonmagic.brain.previousWeek', () => brainSidebarProvider.previousWeek()),
    vscode.commands.registerCommand('jonmagic.brain.nextWeek', () => brainSidebarProvider.nextWeek()),
    vscode.commands.registerCommand('jonmagic.brain.goToCurrentWeek', () => brainSidebarProvider.goToCurrentWeek()),
    vscode.commands.registerCommand('jonmagic.brain.refresh', () => brainSidebarProvider.refresh())
  )

  // Watch for file changes in Brain folder to auto-refresh sidebar
  const brainPath = vscode.workspace.getConfiguration('jonmagic.brain').get<string>('path', '~/Brain').replace(/^~/, process.env.HOME || '')
  const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(brainPath, '**/*.md'))
  watcher.onDidChange(() => brainSidebarProvider.refresh())
  watcher.onDidCreate(() => brainSidebarProvider.refresh())
  watcher.onDidDelete(() => brainSidebarProvider.refresh())
  context.subscriptions.push(watcher)

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
        if (result.weeklyNoteUpdated === false && result.weeklyNotePath) {
          await vscode.window.showWarningMessage(
            `Weekly note not updated: ${result.weeklyNotePath}`
          )
        }
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
