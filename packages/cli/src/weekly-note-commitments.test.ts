import { describe, expect, test } from "bun:test"

import {
  buildLaunchFocusCardCommand,
  buildLaunchWeeklyTodoCommand,
  buildWeeklyTodoPrompt,
  formatWeeklyFocus,
  formatWeeklyFocusCard,
} from "./weekly-note-commitments.js"

import type { BrainTask } from "@jonmagic/scripts-core"

function task(title: string, overrides: Partial<BrainTask> = {}): BrainTask {
  return {
    id: `PVTI_${title.replace(/\W/g, "")}`,
    title,
    status: "Todo",
    week: "Week of 2026-07-26",
    focus: null,
    area: null,
    source: null,
    target: null,
    updated: null,
    ...overrides,
  }
}

describe("weekly note commitment CLI helpers", () => {
  test("formats a sparse weekly focus view", () => {
    expect(
      formatWeeklyFocus({
        tasks: [
          task("Ship the current PR", { area: "tech-debt" }),
          task("Write the follow-up ask"),
        ],
        waiting: [task("Waiting on review", { status: "Waiting" })],
      })
    ).toBe(
      [
        "Brain Tasks: week:@current",
        "Now: Ship the current PR (tech-debt)",
        "Next: Write the follow-up ask",
        "Waiting: Waiting on review",
        "Open: 3",
      ].join("\n")
    )
  })

  test("formats empty weekly focus states", () => {
    expect(formatWeeklyFocus({ tasks: [], waiting: [] })).toBe(
      [
        "Brain Tasks: week:@current",
        "Now: (none)",
        "Next: (none)",
        "Waiting: (none)",
        "Open: 0",
      ].join("\n")
    )
  })

  test("formats a focus card capped by the supplied focus model", () => {
    expect(
      formatWeeklyFocusCard({
        tasks: ["One", "Two", "Three", "Four", "Five"].map((title) =>
          task(title)
        ),
        waiting: [task("Waiting on review", { status: "Waiting" })],
      })
    ).toBe(
      [
        "Weekly Focus",
        "============",
        "",
        "Next items",
        "1. One",
        "2. Two",
        "3. Three",
        "4. Four",
        "5. Five",
        "",
        "Waiting",
        "- Waiting on review",
        "",
        "Source: Brain Tasks board (week:@current)",
      ].join("\n")
    )
  })

  test("builds Copilot prompts for selected tasks", () => {
    const prompt = buildWeeklyTodoPrompt("Ship the current PR")

    expect(prompt).toContain("this task from my Brain Tasks board")
    expect(prompt).toContain("Ship the current PR")
    expect(prompt).toContain("Brain Tasks board is the canonical task store")
  })

  test("builds cmux launch args without interpolating TODO text into shell command", () => {
    const todo = 'Fix $(touch /tmp/nope) and "quote" this'
    const command = buildLaunchWeeklyTodoCommand({
      brainRoot: "/tmp/Brain",
      cmuxPath: "/bin/cmux",
      todo,
    })

    expect(command.command).toBe("/bin/cmux")
    expect(command.args).toContain("new-workspace")
    expect(command.args).toContain("--env")
    expect(command.args).toContain("--command")
    expect(command.args[command.args.indexOf("--cwd") + 1]).toBe("/tmp/Brain")
    expect(command.args[command.args.indexOf("--command") + 1]).toBe(
      'if command -v c >/dev/null 2>&1; then c -i "$WEEKLY_FOCUS_PROMPT"; else copilot --allow-all -i "$WEEKLY_FOCUS_PROMPT"; fi'
    )
    expect(command.args[command.args.indexOf("--env") + 1]).toContain(todo)
    expect(command.args[command.args.indexOf("--command") + 1]).not.toContain(
      todo
    )
  })

  test("builds cmux launch args for the standalone focus card", () => {
    expect(
      buildLaunchFocusCardCommand({
        brainRoot: "/tmp/Brain",
        cmuxPath: "/bin/cmux",
      })
    ).toEqual({
      command: "/bin/cmux",
      args: [
        "new-workspace",
        "--name",
        "Weekly Focus",
        "--cwd",
        "/tmp/Brain",
        "--command",
        "clear && weekly-focus-card",
        "--focus",
        "true",
      ],
    })
  })
})
