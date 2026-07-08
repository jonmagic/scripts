import {
  appendWeeklyNoteCapture,
  parseWeeklyNoteFocus,
  type AppendWeeklyNoteCaptureResult,
  type WeeklyNoteFocus,
} from "@jonmagic/scripts-core"
import { spawn } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

export interface CaptureWeeklyNoteCliOptions {
  brainRoot?: string
  source?: string
  text: string
  weeklyNotePath?: string
}

export interface WeeklyFocusCliOptions {
  brainRoot?: string
  todoLimit?: number
  weeklyNotePath?: string
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
    "I want to work on this weekly note TODO item:",
    "",
    todo,
    "",
    "Start in my Brain. Read the current weekly note for context, then help me clarify the next action and work the item end-to-end. Keep the weekly note as the canonical commitment store.",
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
): Promise<AppendWeeklyNoteCaptureResult> {
  const captureOptions: Parameters<typeof appendWeeklyNoteCapture>[0] = {
    text: options.text,
  }

  if (options.brainRoot !== undefined) {
    captureOptions.brainRoot = options.brainRoot
  }
  if (options.source !== undefined) {
    captureOptions.source = options.source
  }
  if (options.weeklyNotePath !== undefined) {
    captureOptions.weeklyNotePath = options.weeklyNotePath
  }

  return appendWeeklyNoteCapture(captureOptions)
}

export async function runWeeklyFocus(
  options: WeeklyFocusCliOptions
): Promise<WeeklyNoteFocus> {
  const focusOptions: Parameters<typeof parseWeeklyNoteFocus>[0] = {}

  if (options.brainRoot !== undefined) {
    focusOptions.brainRoot = options.brainRoot
  }
  if (options.todoLimit !== undefined) {
    focusOptions.todoLimit = options.todoLimit
  }
  if (options.weeklyNotePath !== undefined) {
    focusOptions.weeklyNotePath = options.weeklyNotePath
  }

  return parseWeeklyNoteFocus(focusOptions)
}

export function formatWeeklyFocus(focus: WeeklyNoteFocus): string {
  const waiting = focus.waiting.length > 0 ? focus.waiting.join("; ") : "(none)"
  const capturedLabel = focus.capturedCount === 1 ? "item" : "items"

  return [
    `Weekly note: ${focus.weeklyNotePath}`,
    `Now: ${focus.now ?? "(none)"}`,
    `Next: ${focus.next ?? "(none)"}`,
    `Waiting: ${waiting}`,
    `Captured: ${focus.capturedCount} unchecked ${capturedLabel}`,
  ].join("\n")
}

export function formatWeeklyFocusCard(focus: WeeklyNoteFocus): string {
  const todos =
    focus.todos.length > 0
      ? focus.todos.map((todo, index) => `${index + 1}. ${todo}`)
      : ["(none)"]
  const waiting =
    focus.waiting.length > 0
      ? focus.waiting.map((item) => `- ${item}`)
      : ["- (none)"]
  const capturedLabel = focus.capturedCount === 1 ? "item" : "items"

  return [
    "Weekly Focus",
    "============",
    "",
    "Next items",
    ...todos,
    "",
    "Waiting",
    ...waiting,
    "",
    `Captured: ${focus.capturedCount} unchecked ${capturedLabel}`,
    "",
    `Source: ${focus.weeklyNotePath}`,
  ].join("\n")
}
