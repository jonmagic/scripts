import * as vscode from "vscode"

import { createDailyProjectNote } from "@jonmagic/scripts-core"
import { getWorkspaceCache, disposeWorkspaceCache } from "./cache/workspaceCache"
import { WikilinkDocumentLinkProvider } from "./features/DocumentLinkProvider"
import { WikilinkCompletionProvider } from "./features/CompletionProvider"
import { registerFileRenameHandler } from "./features/FileRenameHandler"
import { registerOpenDocumentCommand } from "./commands/openDocumentByReference"
import { registerAddFrontmatterCommand } from "./commands/addFrontmatter"
import { registerCreateBookmarkCommand } from "./commands/createBookmark"
import { BrainSidebarProvider } from "./sidebar/BrainSidebarProvider"

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  // Initialize workspace cache - fast init blocks, full init runs in background
  const cache = getWorkspaceCache()
  await cache.initializeFast()
  void cache.initializeFull()

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
  registerCreateBookmarkCommand(context)

  // Register Brain sidebar tree view
  const brainSidebarProvider = new BrainSidebarProvider()
  vscode.window.registerTreeDataProvider('brainWeekView', brainSidebarProvider)

  // Register Brain navigation commands
  context.subscriptions.push(
    vscode.commands.registerCommand('jonmagic.previousWeek', () => brainSidebarProvider.previousWeek()),
    vscode.commands.registerCommand('jonmagic.nextWeek', () => brainSidebarProvider.nextWeek()),
    vscode.commands.registerCommand('jonmagic.goToCurrentWeek', () => brainSidebarProvider.goToCurrentWeek()),
    vscode.commands.registerCommand('jonmagic.refresh', () => brainSidebarProvider.refresh())
  )

  // Register Brain file context menu commands
  context.subscriptions.push(
    vscode.commands.registerCommand('jonmagic.deleteFile', async (item: { resourceUri?: vscode.Uri }) => {
      if (!item.resourceUri) return
      const fileName = item.resourceUri.fsPath.split('/').pop() || 'this file'
      const answer = await vscode.window.showWarningMessage(
        `Delete "${fileName}"?`,
        { modal: true },
        'Delete'
      )
      if (answer === 'Delete') {
        await vscode.workspace.fs.delete(item.resourceUri)
        brainSidebarProvider.refresh()
      }
    }),
    vscode.commands.registerCommand('jonmagic.revealInFinder', (item: { resourceUri?: vscode.Uri }) => {
      if (!item.resourceUri) return
      vscode.commands.executeCommand('revealFileInOS', item.resourceUri)
    }),
    vscode.commands.registerCommand('jonmagic.copyPath', async (item: { resourceUri?: vscode.Uri }) => {
      if (!item.resourceUri) return
      await vscode.env.clipboard.writeText(item.resourceUri.fsPath)
      vscode.window.showInformationMessage('Path copied to clipboard')
    }),
    vscode.commands.registerCommand('jonmagic.copyFileContents', async (item: { resourceUri?: vscode.Uri }) => {
      if (!item.resourceUri) return
      const content = await vscode.workspace.fs.readFile(item.resourceUri)
      await vscode.env.clipboard.writeText(Buffer.from(content).toString('utf-8'))
      vscode.window.showInformationMessage('File contents copied to clipboard')
    })
  )

  // Watch for file changes in Brain folder to auto-refresh sidebar
  const brainPath = vscode.workspace.getConfiguration('jonmagic').get<string>('brainPath', '~/Brain').replace(/^~/, process.env.HOME || '')
  const brainUri = vscode.Uri.file(brainPath)
  const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(brainUri, '**/*.md'))
  watcher.onDidChange(() => brainSidebarProvider.refresh())
  watcher.onDidCreate(() => brainSidebarProvider.refresh())
  watcher.onDidDelete(() => brainSidebarProvider.refresh())
  context.subscriptions.push(watcher)

  // Register daily project note command
  const createNoteDisposable = vscode.commands.registerCommand(
    "jonmagic.createDailyProjectNote",
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
