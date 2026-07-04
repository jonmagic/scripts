import * as cp from "node:child_process"
import * as vscode from "vscode"
import { getWorkspaceCache } from "../cache/workspaceCache"
import { getBrainPath } from "../config/brainPath"
import { rankRecentBrainFiles } from "./recentBrainFileRanking"

interface RecentBrainQuickPickItem extends vscode.QuickPickItem {
  absolutePath: string
}

const RECENT_FILE_LIMIT = 50

function execFile(
  command: string,
  args: string[],
  options: cp.ExecFileOptions
): Promise<string> {
  return new Promise((resolve, reject) => {
    cp.execFile(command, args, options, (error, stdout) => {
      if (error) {
        reject(error instanceof Error ? error : new Error("Command failed"))
        return
      }

      resolve(String(stdout))
    })
  })
}

function parseGitStatusLine(line: string): [string, string] | null {
  if (line.length < 4) {
    return null
  }

  const status = line.slice(0, 2).trim()
  const rawPath = line.slice(3)
  const renamedPath = rawPath.includes(" -> ")
    ? rawPath.slice(rawPath.lastIndexOf(" -> ") + 4)
    : rawPath
  const relativePath = renamedPath.replace(/^"|"$/g, "")

  if (!relativePath.endsWith(".md")) {
    return null
  }

  return [relativePath, status || "modified"]
}

export async function getGitMarkdownStatuses(
  brainRoot: string
): Promise<Map<string, string>> {
  const output = await execFile(
    "git",
    [
      "-C",
      brainRoot,
      "-c",
      "core.quotePath=false",
      "status",
      "--porcelain",
      "--untracked-files=all",
    ],
    { timeout: 10000 }
  )
  const statuses = new Map<string, string>()

  for (const line of output.split(/\r?\n/)) {
    const parsed = parseGitStatusLine(line)
    if (!parsed) {
      continue
    }

    const [relativePath, status] = parsed
    statuses.set(relativePath, status)
  }

  return statuses
}

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
  const cache = getWorkspaceCache()
  const brainRoot = getBrainPath()

  if (!cache.hasFullIndex()) {
    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Loading Brain files...",
        cancellable: false,
      },
      () => cache.initializeFull()
    )
  }

  let gitStatuses = new Map<string, string>()
  try {
    gitStatuses = await getGitMarkdownStatuses(brainRoot)
  } catch {
    vscode.window.showWarningMessage(
      "Could not read Brain git status; showing recent files by modified time."
    )
  }

  const rankedFiles = rankRecentBrainFiles(
    cache.getAllFiles(),
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
