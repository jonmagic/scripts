import { spawn } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

/**
 * The Brain Tasks board is the canonical store for @jonmagic's open work.
 *
 * Every writer goes through the `brain-tasks` CLI rather than reimplementing the
 * Projects V2 field ids in a third language. It already owns iteration
 * resolution, single-select option ids, and the local read cache.
 */

export interface BrainTask {
  id: string
  title: string
  status: string
  week: string | null
  focus: number | null
  area: string | null
  source: string | null
  target: string | null
  updated: string | null
}

export interface AddBrainTaskOptions {
  title: string
  /** Defaults to `Todo` so captured work is actionable, not triage. */
  status?: string
  /**
   * Defaults to `current`. Weekly Focus queries the board with `week:@current`,
   * so a task with no week is invisible until the next weekly roll.
   */
  week?: string
  source?: string
  target?: string
  area?: string
  body?: string
  brainTasksPath?: string
}

export interface AddBrainTaskResult {
  id: string
  title: string
}

export interface ListBrainTasksOptions {
  week?: string
  status?: string
  focusOnly?: boolean
  brainTasksPath?: string
}

export function defaultBrainTasksPath(): string {
  return path.join(
    os.homedir(),
    ".copilot",
    "skills",
    "brain",
    "scripts",
    "brain-tasks"
  )
}

export function buildAddBrainTaskArgs(options: AddBrainTaskOptions): string[] {
  const title = options.title.trim()
  if (!title) {
    throw new Error("Task title is required")
  }

  const args = [
    "add",
    "--title",
    title,
    "--status",
    options.status ?? "Todo",
    "--week",
    options.week ?? "current",
    "--json",
  ]

  for (const [flag, value] of [
    ["--source", options.source],
    ["--target", options.target],
    ["--area", options.area],
    ["--body", options.body],
  ] as const) {
    if (value && value.trim()) {
      args.push(flag, value.trim())
    }
  }

  return args
}

export function buildListBrainTasksArgs(
  options: ListBrainTasksOptions = {}
): string[] {
  const args = ["list", "--week", options.week ?? "current", "--json"]
  if (options.status) {
    args.push("--status", options.status)
  }
  if (options.focusOnly) {
    args.push("--focus")
  }
  return args
}

async function runBrainTasks(
  args: string[],
  brainTasksPath?: string
): Promise<string> {
  const executable = brainTasksPath || defaultBrainTasksPath()
  if (!fs.existsSync(executable)) {
    throw new Error(`brain-tasks not found at ${executable}`)
  }

  return new Promise<string>((resolve, reject) => {
    // GUI hosts such as Raycast and VS Code do not inherit a login shell PATH,
    // and brain-tasks shells out to `gh`.
    const child = spawn(executable, args, {
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        PATH: [
          process.env.PATH,
          "/opt/homebrew/bin",
          "/usr/local/bin",
          "/usr/bin",
          "/bin",
        ]
          .filter(Boolean)
          .join(":"),
      },
    })

    let stdout = ""
    let stderr = ""
    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString()
    })
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString()
    })
    child.on("error", (error) => reject(error))
    child.on("close", (code) => {
      if (code === 0) {
        resolve(stdout)
      } else {
        reject(new Error(stderr.trim() || `brain-tasks exited with ${code}`))
      }
    })
  })
}

export async function addBrainTask(
  options: AddBrainTaskOptions
): Promise<AddBrainTaskResult> {
  const output = await runBrainTasks(
    buildAddBrainTaskArgs(options),
    options.brainTasksPath
  )

  const parsed = JSON.parse(output) as { id: string; title: string }
  return { id: parsed.id, title: parsed.title }
}

export async function listBrainTasks(
  options: ListBrainTasksOptions = {}
): Promise<BrainTask[]> {
  const output = await runBrainTasks(
    buildListBrainTasksArgs(options),
    options.brainTasksPath
  )

  return JSON.parse(output) as BrainTask[]
}
