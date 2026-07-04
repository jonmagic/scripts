import * as cp from "node:child_process"
import * as vscode from "vscode"
import { getWorkspaceCache } from "../cache/workspaceCache"
import { getBrainPath } from "../config/brainPath"
import { rankRecentBrainFiles } from "./recentBrainFileRanking"

interface RecentBrainQuickPickItem extends vscode.QuickPickItem {
  absolutePath: string
}

const RECENT_FILE_LIMIT = 50
const GIT_LIST_TIMEOUT_MS = 100

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

export async function getGitMarkdownStatuses(
  brainRoot: string
): Promise<Map<string, string>> {
  const gitPrefix = ["-C", brainRoot, "-c", "core.quotePath=false"]
  const [unstaged, staged] = await Promise.all([
    execFile("git", [...gitPrefix, "diff", "--name-only", "--", "*.md"], {
      timeout: GIT_LIST_TIMEOUT_MS,
    }),
    execFile(
      "git",
      [...gitPrefix, "diff", "--name-only", "--cached", "--", "*.md"],
      { timeout: GIT_LIST_TIMEOUT_MS }
    ),
  ])
  const statuses = new Map<string, string>()

  for (const relativePath of `${staged}\n${unstaged}`.split(/\r?\n/)) {
    if (!relativePath.endsWith(".md")) {
      continue
    }

    statuses.set(relativePath, "modified")
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

  if (!cache.isReady()) {
    await cache.initializeFast()
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
