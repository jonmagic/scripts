import {
  addBrainTask,
  listBrainTasks,
  type AddBrainTaskResult,
  type BrainTask,
} from "@jonmagic/scripts-core"
import { spawn } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

export interface CaptureWeeklyNoteCliOptions {
  brainTasksPath?: string
  source?: string
  text: string
}

export interface WeeklyFocusCliOptions {
  brainTasksPath?: string
  todoLimit?: number
}

export interface WeeklyFocus {
  tasks: BrainTask[]
  waiting: BrainTask[]
}

export interface LaunchWeeklyTodoOptions {
  brainRoot?: string
  cmuxPath?: string
  todo: string
}

export interface LaunchFocusCardOptions {
  brainRoot?: string
  cmuxPath?: string
}

export interface LaunchCommand {
  command: string
  args: string[]
}

const COPILOT_PROMPT_ENV = "WEEKLY_FOCUS_PROMPT"
const COPILOT_COMMAND =
  `if command -v c >/dev/null 2>&1; then c -i "$${COPILOT_PROMPT_ENV}"; else copilot --allow-all -i "$${COPILOT_PROMPT_ENV}"; fi`
const CMUX_CANDIDATES = [
  "/Applications/cmux.app/Contents/Resources/bin/cmux",
  "/opt/homebrew/bin/cmux",
  "/usr/local/bin/cmux",
]

function resolveBrainRootPath(brainRoot?: string): string {
  const configured = brainRoot ?? "~/Brain"

  if (configured === "~") {
    return os.homedir()
  }

  if (configured.startsWith("~/")) {
    return path.join(os.homedir(), configured.slice(2))
  }

  return configured
}

function workspaceTitleForTodo(todo: string): string {
  const normalized = todo.replace(/\s+/g, " ").trim()
  return normalized.length > 60 ? `${normalized.slice(0, 57)}...` : normalized
}

function resolveCmuxCommand(cmuxPath?: string): string {
  if (cmuxPath) {
    return cmuxPath
  }

  for (const candidate of CMUX_CANDIDATES) {
    if (fs.existsSync(candidate)) {
      return candidate
    }
  }

  return "cmux"
}

export function buildWeeklyTodoPrompt(todo: string): string {
  return [
    "I want to work on this task from my Brain Tasks board:",
    "",
    todo,
    "",
    "Start in my Brain. Read the current weekly note for context, then help me clarify the next action and work the item end-to-end. The Brain Tasks board is the canonical task store, so record status changes there with brain-tasks rather than in the weekly note.",
  ].join("\n")
}

export function buildLaunchWeeklyTodoCommand(
  options: LaunchWeeklyTodoOptions
): LaunchCommand {
  const brainRoot = resolveBrainRootPath(options.brainRoot)
  const prompt = buildWeeklyTodoPrompt(options.todo)

  return {
    command: resolveCmuxCommand(options.cmuxPath),
    args: [
      "new-workspace",
      "--name",
      workspaceTitleForTodo(options.todo),
      "--cwd",
      brainRoot,
      "--env",
      `${COPILOT_PROMPT_ENV}=${prompt}`,
      "--command",
      COPILOT_COMMAND,
      "--focus",
      "true",
    ],
  }
}

export function buildLaunchFocusCardCommand(
  options: LaunchFocusCardOptions = {}
): LaunchCommand {
  const brainRoot = resolveBrainRootPath(options.brainRoot)

  return {
    command: resolveCmuxCommand(options.cmuxPath),
    args: [
      "new-workspace",
      "--name",
      "Weekly Focus",
      "--cwd",
      brainRoot,
      "--command",
      "clear && weekly-focus-card",
      "--focus",
      "true",
    ],
  }
}

async function runLaunchCommand(launchCommand: LaunchCommand): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(launchCommand.command, launchCommand.args, {
      stdio: "ignore",
      detached: true,
    })
    child.once("error", reject)
    child.once("spawn", () => {
      child.unref()
      resolve()
    })
  })
}

export async function launchWeeklyTodo(
  options: LaunchWeeklyTodoOptions
): Promise<void> {
  await runLaunchCommand(buildLaunchWeeklyTodoCommand(options))
}

export async function launchFocusCard(
  options: LaunchFocusCardOptions = {}
): Promise<void> {
  await runLaunchCommand(buildLaunchFocusCardCommand(options))
}

export async function runCaptureWeeklyNote(
  options: CaptureWeeklyNoteCliOptions
): Promise<AddBrainTaskResult> {
  const addOptions: Parameters<typeof addBrainTask>[0] = {
    title: options.text,
  }

  if (options.source !== undefined) {
    addOptions.source = options.source
  }
  if (options.brainTasksPath !== undefined) {
    addOptions.brainTasksPath = options.brainTasksPath
  }

  return addBrainTask(addOptions)
}

const WAITING_STATUS = "Waiting"
const ACTIVE_STATUSES = "Todo,Doing,Waiting"

export async function runWeeklyFocus(
  options: WeeklyFocusCliOptions = {}
): Promise<WeeklyFocus> {
  const listOptions: Parameters<typeof listBrainTasks>[0] = {
    status: ACTIVE_STATUSES,
  }

  if (options.brainTasksPath !== undefined) {
    listOptions.brainTasksPath = options.brainTasksPath
  }

  const items = await listBrainTasks(listOptions)
  const waiting = items.filter((item) => item.status === WAITING_STATUS)
  const actionable = items.filter((item) => item.status !== WAITING_STATUS)
  const limit = options.todoLimit ?? 5

  return { tasks: actionable.slice(0, limit), waiting }
}

function taskLabel(task: BrainTask): string {
  return task.area ? `${task.title} (${task.area})` : task.title
}

export function formatWeeklyFocus(focus: WeeklyFocus): string {
  const [now, next] = focus.tasks
  const waiting =
    focus.waiting.length > 0
      ? focus.waiting.map(taskLabel).join("; ")
      : "(none)"

  return [
    "Brain Tasks: week:@current",
    `Now: ${now ? taskLabel(now) : "(none)"}`,
    `Next: ${next ? taskLabel(next) : "(none)"}`,
    `Waiting: ${waiting}`,
    `Open: ${focus.tasks.length + focus.waiting.length}`,
  ].join("\n")
}

export function formatWeeklyFocusCard(focus: WeeklyFocus): string {
  const tasks =
    focus.tasks.length > 0
      ? focus.tasks.map((task, index) => `${index + 1}. ${taskLabel(task)}`)
      : ["(none)"]
  const waiting =
    focus.waiting.length > 0
      ? focus.waiting.map((task) => `- ${taskLabel(task)}`)
      : ["- (none)"]

  return [
    "Weekly Focus",
    "============",
    "",
    "Next items",
    ...tasks,
    "",
    "Waiting",
    ...waiting,
    "",
    "Source: Brain Tasks board (week:@current)",
  ].join("\n")
}
