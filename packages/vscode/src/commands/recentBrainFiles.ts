import * as cp from "node:child_process"
import * as fs from "node:fs/promises"
import * as path from "node:path"
import * as vscode from "vscode"
import { getBrainPath, getRelativeBrainPath } from "../config/brainPath"
import {
  rankRecentBrainFiles,
  type RecentBrainFileCandidate,
} from "./recentBrainFileRanking"

interface RecentBrainQuickPickItem extends vscode.QuickPickItem {
  absolutePath: string
}

const RECENT_FILE_LIMIT = 50
const GIT_COMMAND_TIMEOUT_MS = 100
const GIT_HISTORY_COMMIT_LIMIT = 50

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
      timeout: GIT_COMMAND_TIMEOUT_MS,
    }),
    execFile(
      "git",
      [...gitPrefix, "diff", "--name-only", "--cached", "--", "*.md"],
      { timeout: GIT_COMMAND_TIMEOUT_MS }
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

async function execFileOrEmpty(
  command: string,
  args: string[],
  options: cp.ExecFileOptions
): Promise<string> {
  try {
    return await execFile(command, args, options)
  } catch {
    return ""
  }
}

function markdownPathsFromOutput(output: string): string[] {
  const seen = new Set<string>()
  const paths: string[] = []

  for (const relativePath of output.split(/\r?\n/)) {
    if (!relativePath.endsWith(".md") || seen.has(relativePath)) {
      continue
    }

    seen.add(relativePath)
    paths.push(relativePath)
  }

  return paths
}

function formatDate(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

function getWeekStart(date: Date): Date {
  const start = new Date(date)
  start.setHours(0, 0, 0, 0)
  start.setDate(start.getDate() - start.getDay())
  return start
}

async function getRecentGitMarkdownPaths(brainRoot: string): Promise<string[]> {
  const output = await execFileOrEmpty(
    "git",
    [
      "-C",
      brainRoot,
      "-c",
      "core.quotePath=false",
      "log",
      "--name-only",
      "--pretty=format:",
      "-n",
      String(GIT_HISTORY_COMMIT_LIMIT),
      "--",
      "*.md",
    ],
    { timeout: GIT_COMMAND_TIMEOUT_MS }
  )

  return markdownPathsFromOutput(output)
}

async function addFileCandidate(
  candidates: Map<string, RecentBrainFileCandidate>,
  brainRoot: string,
  absolutePath: string
): Promise<void> {
  const relativePath = getRelativeBrainPath(absolutePath, brainRoot)
  if (!relativePath?.endsWith(".md") || candidates.has(relativePath)) {
    return
  }

  try {
    const stat = await fs.stat(absolutePath)
    if (!stat.isFile()) {
      return
    }

    candidates.set(relativePath, {
      absolutePath,
      relativePath,
      mtime: stat.mtimeMs,
    })
  } catch {
    // Recent git history may reference deleted or renamed files.
  }
}

async function addMarkdownFilesFromDirectory(
  candidates: Map<string, RecentBrainFileCandidate>,
  brainRoot: string,
  directoryPath: string
): Promise<void> {
  try {
    const entries = await fs.readdir(directoryPath, { withFileTypes: true })
    await Promise.all(
      entries
        .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
        .map((entry) =>
          addFileCandidate(candidates, brainRoot, path.join(directoryPath, entry.name))
        )
    )
  } catch {
    // Focused date folders may not exist yet.
  }
}

async function getFastRecentBrainFiles(
  brainRoot: string
): Promise<RecentBrainFileCandidate[]> {
  const candidates = new Map<string, RecentBrainFileCandidate>()
  const today = new Date()
  const todayFolder = path.join(
    brainRoot,
    "Daily Projects",
    formatDate(today)
  )
  const weeklyNotePath = path.join(
    brainRoot,
    "Weekly Notes",
    `Week of ${formatDate(getWeekStart(today))}.md`
  )
  const recentGitPaths = await getRecentGitMarkdownPaths(brainRoot)

  await Promise.all([
    addMarkdownFilesFromDirectory(candidates, brainRoot, todayFolder),
    addFileCandidate(candidates, brainRoot, weeklyNotePath),
    ...recentGitPaths
      .slice(0, RECENT_FILE_LIMIT)
      .map((relativePath) =>
        addFileCandidate(candidates, brainRoot, path.join(brainRoot, relativePath))
      ),
  ])

  return Array.from(candidates.values())
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
    await getFastRecentBrainFiles(brainRoot),
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
