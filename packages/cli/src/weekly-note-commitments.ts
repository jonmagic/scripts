import {
  appendWeeklyNoteCapture,
  parseWeeklyNoteFocus,
  type AppendWeeklyNoteCaptureResult,
  type WeeklyNoteFocus,
} from "@jonmagic/scripts-core"

export interface CaptureWeeklyNoteCliOptions {
  brainRoot?: string
  source?: string
  text: string
  weeklyNotePath?: string
}

export interface WeeklyFocusCliOptions {
  brainRoot?: string
  weeklyNotePath?: string
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
