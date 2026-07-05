import * as vscode from "vscode"
import * as path from "node:path"

import {
  createDailyProjectNote,
  formatLocalDateYYYYMMDD,
  parseLocalDateYYYYMMDD,
} from "@jonmagic/scripts-core"
import {
  getWorkspaceCache,
  disposeWorkspaceCache,
  startWorkspaceCacheInitialization,
} from "./cache/workspaceCache"
import {
  getBrainPath,
  getBrainRootUri,
  getRelativeBrainPath,
} from "./config/brainPath"
import { WikilinkDocumentLinkProvider } from "./features/DocumentLinkProvider"
import { WikilinkCompletionProvider } from "./features/CompletionProvider"
import { registerFileRenameHandler } from "./features/FileRenameHandler"
import { registerOpenDocumentCommand } from "./commands/openDocumentByReference"
import { registerAddFrontmatterCommand } from "./commands/addFrontmatter"
import { registerCreateBookmarkCommand } from "./commands/createBookmark"
import { registerBrainCollectionQuickPickCommands } from "./commands/brainCollectionQuickPicks"
import { registerRecentBrainFilesCommand } from "./commands/recentBrainFiles"
import { registerTypedBrainActionCommands } from "./commands/typedBrainActions"
import {
  extendBrainMarkdownIt,
  type MarkdownItLike,
} from "./markdown/wikiLinks"
import { BrainSidebarProvider } from "./sidebar/BrainSidebarProvider"

interface MarkdownExtensionApi {
  extendMarkdownIt(md: MarkdownItLike): MarkdownItLike
}

type ResourceTarget = vscode.Uri | { resourceUri?: vscode.Uri }

function getResourceUri(target: ResourceTarget): vscode.Uri | undefined {
  if (target instanceof vscode.Uri) {
    return target
  }

  return target.resourceUri
}

function getDefaultDailyProjectDateInput(): string {
  return formatLocalDateYYYYMMDD(new Date())
}

function validateDailyProjectDateInput(value: string): string | null {
  try {
    parseLocalDateYYYYMMDD(value)
    return null
  } catch (error) {
    return error instanceof Error ? error.message : String(error)
  }
}

function createBrainWatcher(
  onChange: () => void,
  shouldIgnore: (uri: vscode.Uri) => Thenable<boolean>
): vscode.FileSystemWatcher {
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(getBrainRootUri(), "**/*.md")
  )
  const handleChange = (uri: vscode.Uri) => {
    void shouldIgnore(uri).then((ignored) => {
      if (!ignored) {
        onChange()
      }
    })
  }
  watcher.onDidChange(handleChange)
  watcher.onDidCreate(handleChange)
  watcher.onDidDelete(handleChange)
  return watcher
}

function shouldInitializeWorkspaceCacheForEditor(
  editor: vscode.TextEditor | undefined
): boolean {
  if (!editor || editor.document.languageId !== "markdown") {
    return false
  }

  if (editor.document.uri.scheme !== "file") {
    return false
  }

  return getRelativeBrainPath(editor.document.uri.fsPath) !== null
}

function startWorkspaceCacheForEditor(
  editor: vscode.TextEditor | undefined
): void {
  if (shouldInitializeWorkspaceCacheForEditor(editor)) {
    startWorkspaceCacheInitialization()
  }
}

async function executeResourceCommand(
  command: string,
  resourceUri: vscode.Uri,
  unavailableMessage: string
): Promise<void> {
  const commands = await vscode.commands.getCommands(true)
  if (!commands.includes(command)) {
    await vscode.window.showErrorMessage(unavailableMessage)
    return
  }

  await vscode.commands.executeCommand(command, resourceUri)
}

async function openPreview(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  await executeResourceCommand(
    "markdown.showPreview",
    resourceUri,
    "Markdown preview command is not available"
  )
}

async function openToSide(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  await vscode.commands.executeCommand("vscode.open", resourceUri, {
    preview: false,
    viewColumn: vscode.ViewColumn.Beside,
  })
}

async function openWith(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  await executeResourceCommand(
    "explorer.openWith",
    resourceUri,
    "Open With command is not available"
  )
}

async function revealInFinder(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  await vscode.commands.executeCommand("revealFileInOS", resourceUri)
}

async function addFileToChat(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  await executeResourceCommand(
    "github.copilot.chat.attachFile",
    resourceUri,
    "Add File to Chat command is not available"
  )
}

async function copyFileContents(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  const content = await vscode.workspace.fs.readFile(resourceUri)
  await vscode.env.clipboard.writeText(Buffer.from(content).toString("utf-8"))
  vscode.window.showInformationMessage("File contents copied to clipboard")
}

async function copyPath(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  await vscode.env.clipboard.writeText(resourceUri.fsPath)
  vscode.window.showInformationMessage("Path copied to clipboard")
}

async function copyRelativePath(target: ResourceTarget): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  const relativePath = getRelativeBrainPath(resourceUri.fsPath)
  if (!relativePath) {
    vscode.window.showErrorMessage(
      `File is outside the configured Brain folder: ${getBrainPath()}`
    )
    return
  }

  await vscode.env.clipboard.writeText(relativePath)
  vscode.window.showInformationMessage("Relative path copied to clipboard")
}

async function renameFile(
  target: ResourceTarget,
  onRenamed: () => void
): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  const currentName = path.basename(resourceUri.fsPath)
  const extensionStart = currentName.lastIndexOf(".")
  const newName = await vscode.window.showInputBox({
    title: "Rename File",
    value: currentName,
    valueSelection: [
      0,
      extensionStart > 0 ? extensionStart : currentName.length,
    ],
  })

  if (!newName || newName === currentName) {
    return
  }

  if (newName.includes("/") || newName.includes("\\")) {
    vscode.window.showErrorMessage("File name cannot contain path separators")
    return
  }

  const newUri = vscode.Uri.file(path.join(path.dirname(resourceUri.fsPath), newName))
  const edit = new vscode.WorkspaceEdit()
  edit.renameFile(resourceUri, newUri)
  const applied = await vscode.workspace.applyEdit(edit)
  if (!applied) {
    vscode.window.showErrorMessage(`Could not rename ${currentName}`)
    return
  }

  onRenamed()
}

async function deleteFile(
  target: ResourceTarget,
  onDeleted: () => void
): Promise<void> {
  const resourceUri = getResourceUri(target)
  if (!resourceUri) return

  const fileName = path.basename(resourceUri.fsPath)
  const answer = await vscode.window.showWarningMessage(
    `Delete "${fileName}"?`,
    { modal: true },
    "Delete"
  )
  if (answer === "Delete") {
    await vscode.workspace.fs.delete(resourceUri)
    onDeleted()
  }
}

export function activate(
  context: vscode.ExtensionContext
): MarkdownExtensionApi {
  const cache = getWorkspaceCache()
  startWorkspaceCacheForEditor(vscode.window.activeTextEditor)

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
  registerBrainCollectionQuickPickCommands(context)
  registerRecentBrainFilesCommand(context)

  // Register Brain sidebar tree view
  const brainSidebarProvider = new BrainSidebarProvider()
  const refreshSidebar = () => brainSidebarProvider.refresh()
  const shouldIgnoreSidebarUri = (uri: vscode.Uri) =>
    cache.isIgnoredPath(uri.fsPath)
  registerTypedBrainActionCommands(context, refreshSidebar)

  context.subscriptions.push(
    vscode.window.registerTreeDataProvider("brainWeekView", brainSidebarProvider)
  )
  context.subscriptions.push(
    vscode.window.onDidChangeActiveTextEditor((editor) => {
      brainSidebarProvider.setActiveEditor(editor)
      startWorkspaceCacheForEditor(editor)
    })
  )

  // Register Brain navigation commands
  context.subscriptions.push(
    vscode.commands.registerCommand('jonmagic.previousWeek', () => brainSidebarProvider.previousWeek()),
    vscode.commands.registerCommand('jonmagic.nextWeek', () => brainSidebarProvider.nextWeek()),
    vscode.commands.registerCommand('jonmagic.goToCurrentWeek', () => brainSidebarProvider.goToCurrentWeek()),
    vscode.commands.registerCommand('jonmagic.refresh', refreshSidebar)
  )

  // Register Brain file context menu commands
  context.subscriptions.push(
    vscode.commands.registerCommand("jonmagic.openPreview", openPreview),
    vscode.commands.registerCommand("jonmagic.openToSide", openToSide),
    vscode.commands.registerCommand("jonmagic.openWith", openWith),
    vscode.commands.registerCommand("jonmagic.revealInFinder", revealInFinder),
    vscode.commands.registerCommand("jonmagic.addFileToChat", addFileToChat),
    vscode.commands.registerCommand("jonmagic.copyFile", copyFileContents),
    vscode.commands.registerCommand("jonmagic.copyPath", copyPath),
    vscode.commands.registerCommand("jonmagic.copyRelativePath", copyRelativePath),
    vscode.commands.registerCommand("jonmagic.renameFile", (item: ResourceTarget) =>
      renameFile(item, refreshSidebar)
    ),
    vscode.commands.registerCommand("jonmagic.deleteFile", (item: ResourceTarget) =>
      deleteFile(item, refreshSidebar)
    )
  )

  // Watch for file changes in Brain folder to auto-refresh sidebar
  let watcher = createBrainWatcher(refreshSidebar, shouldIgnoreSidebarUri)
  context.subscriptions.push({
    dispose: () => {
      watcher.dispose()
    },
  })
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (!event.affectsConfiguration("jonmagic.brainPath")) {
        return
      }

      watcher.dispose()
      watcher = createBrainWatcher(refreshSidebar, shouldIgnoreSidebarUri)
      void cache.refresh().then(() => {
        refreshSidebar()
      })
    })
  )

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

      const dateInput = await vscode.window.showInputBox({
        title: "Create Daily Project Note",
        prompt: "Date for the new Daily Project note",
        value: getDefaultDailyProjectDateInput(),
        validateInput: validateDailyProjectDateInput,
      })

      if (dateInput === undefined) {
        return
      }

      try {
        const date = parseLocalDateYYYYMMDD(dateInput)
        const result = await createDailyProjectNote({
          title,
          brainRoot: getBrainPath(),
          date,
        })
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

  return {
    extendMarkdownIt(md: MarkdownItLike): MarkdownItLike {
      return extendBrainMarkdownIt(md)
    },
  }
}

export function deactivate(): void {
  disposeWorkspaceCache()
}
