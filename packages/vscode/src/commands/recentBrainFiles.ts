import * as vscode from "vscode"
import { getBrainPath } from "../config/brainPath"
import {
  getFastRecentBrainFiles,
  getGitMarkdownStatuses,
} from "./recentBrainFileCandidates"
import {
  rankRecentBrainFiles,
} from "./recentBrainFileRanking"

interface RecentBrainQuickPickItem extends vscode.QuickPickItem {
  absolutePath: string
}

const RECENT_FILE_LIMIT = 50

function buildQuickPickItems(
  files: ReturnType<typeof rankRecentBrainFiles>
): RecentBrainQuickPickItem[] {
  return files.map((file) => {
    const modified = file.gitStatus ? `git ${file.gitStatus}` : "recent"
    const mtime = new Date(file.mtime).toLocaleString()

    return {
      label: file.relativePath,
      description: modified,
      detail: mtime,
      absolutePath: file.absolutePath,
    }
  })
}

export async function openRecentBrainFile(): Promise<void> {
  const brainRoot = getBrainPath()

  let gitStatuses = new Map<string, string>()
  try {
    gitStatuses = await getGitMarkdownStatuses(brainRoot)
  } catch {
    vscode.window.showWarningMessage(
      "Could not read Brain git status; showing recent files by modified time."
    )
  }

  const rankedFiles = rankRecentBrainFiles(
    await getFastRecentBrainFiles(brainRoot, { limit: RECENT_FILE_LIMIT }),
    gitStatuses,
    RECENT_FILE_LIMIT
  )
  const items = buildQuickPickItems(rankedFiles)

  if (items.length === 0) {
    vscode.window.showInformationMessage("No recent Brain Markdown files found.")
    return
  }

  const selected = await vscode.window.showQuickPick(items, {
    title: "Open Recent Brain File",
    placeHolder: "Git-modified files are listed first, then recent files",
    matchOnDescription: true,
    matchOnDetail: true,
  })

  if (!selected) {
    return
  }

  const document = await vscode.workspace.openTextDocument(
    vscode.Uri.file(selected.absolutePath)
  )
  await vscode.window.showTextDocument(document, { preview: false })
}

export function registerRecentBrainFilesCommand(
  context: vscode.ExtensionContext
): void {
  const disposable = vscode.commands.registerCommand(
    "jonmagic.openRecentBrainFile",
    openRecentBrainFile
  )
  context.subscriptions.push(disposable)
}
