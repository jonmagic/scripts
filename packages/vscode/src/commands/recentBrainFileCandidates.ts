import * as cp from "node:child_process"
import * as fs from "node:fs/promises"
import * as path from "node:path"

import type { RecentBrainFileCandidate } from "./recentBrainFileRanking"

const DEFAULT_RECENT_FILE_LIMIT = 50
const DEFAULT_GIT_COMMAND_TIMEOUT_MS = 100
const DEFAULT_GIT_HISTORY_COMMIT_LIMIT = 50

interface ErrorWithCode extends Error {
  code?: string
}

export interface FastRecentBrainFileOptions {
  gitHistoryCommitLimit?: number
  limit?: number
  now?: Date
  timeoutMs?: number
}

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

function normalizePath(filePath: string): string {
  return filePath.replace(/\\/g, "/")
}

function isErrorWithCode(error: unknown): error is ErrorWithCode {
  return error instanceof Error && "code" in error
}

function getRelativeBrainPath(
  absolutePath: string,
  brainRoot: string
): string | null {
  const relativePath = path.relative(brainRoot, absolutePath)

  if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
    return null
  }

  return normalizePath(relativePath)
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

async function getRecentGitMarkdownPaths(
  brainRoot: string,
  options: Required<Pick<FastRecentBrainFileOptions, "gitHistoryCommitLimit" | "timeoutMs">>
): Promise<string[]> {
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
      String(options.gitHistoryCommitLimit),
      "--",
      "*.md",
    ],
    { timeout: options.timeoutMs }
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
  } catch (error) {
    if (
      isErrorWithCode(error) &&
      (error.code === "ENOENT" || error.code === "ENOTDIR")
    ) {
      return
    }

    throw error
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
  } catch (error) {
    if (isErrorWithCode(error) && error.code === "ENOENT") {
      return
    }

    throw error
  }
}

export async function getGitMarkdownStatuses(
  brainRoot: string,
  timeoutMs = DEFAULT_GIT_COMMAND_TIMEOUT_MS
): Promise<Map<string, string>> {
  const gitPrefix = ["-C", brainRoot, "-c", "core.quotePath=false"]
  const [unstaged, staged] = await Promise.all([
    execFile("git", [...gitPrefix, "diff", "--name-only", "--", "*.md"], {
      timeout: timeoutMs,
    }),
    execFile(
      "git",
      [...gitPrefix, "diff", "--name-only", "--cached", "--", "*.md"],
      { timeout: timeoutMs }
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

export async function getFastRecentBrainFiles(
  brainRoot: string,
  rawOptions: FastRecentBrainFileOptions = {}
): Promise<RecentBrainFileCandidate[]> {
  const options = {
    gitHistoryCommitLimit:
      rawOptions.gitHistoryCommitLimit ?? DEFAULT_GIT_HISTORY_COMMIT_LIMIT,
    limit: rawOptions.limit ?? DEFAULT_RECENT_FILE_LIMIT,
    now: rawOptions.now ?? new Date(),
    timeoutMs: rawOptions.timeoutMs ?? DEFAULT_GIT_COMMAND_TIMEOUT_MS,
  }
  const candidates = new Map<string, RecentBrainFileCandidate>()
  const todayFolder = path.join(
    brainRoot,
    "Daily Projects",
    formatDate(options.now)
  )
  const weeklyNotePath = path.join(
    brainRoot,
    "Weekly Notes",
    `Week of ${formatDate(getWeekStart(options.now))}.md`
  )
  const recentGitPaths = await getRecentGitMarkdownPaths(brainRoot, options)

  await Promise.all([
    addMarkdownFilesFromDirectory(candidates, brainRoot, todayFolder),
    addFileCandidate(candidates, brainRoot, weeklyNotePath),
    ...recentGitPaths
      .slice(0, options.limit)
      .map((relativePath) =>
        addFileCandidate(candidates, brainRoot, path.join(brainRoot, relativePath))
      ),
  ])

  return Array.from(candidates.values())
}
