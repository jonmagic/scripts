import { describe, expect, test } from "bun:test"

import {
  buildLaunchFocusCardCommand,
  buildLaunchWeeklyTodoCommand,
  buildWeeklyTodoPrompt,
  formatWeeklyFocus,
  formatWeeklyFocusCard,
} from "./weekly-note-commitments.js"

describe("weekly note commitment CLI helpers", () => {
  test("formats a sparse weekly focus view", () => {
    expect(
      formatWeeklyFocus({
        brainRoot: "/tmp/Brain",
        weeklyNotePath: "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
        now: "Ship the current PR",
        next: "Write the follow-up ask",
        todos: ["Ship the current PR", "Write the follow-up ask"],
        waiting: ["Waiting on review"],
        capturedCount: 2,
      })
    ).toBe(
      [
        "Weekly note: /tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
        "Now: Ship the current PR",
        "Next: Write the follow-up ask",
        "Waiting: Waiting on review",
        "Captured: 2 unchecked items",
      ].join("\n")
    )
  })

  test("formats empty weekly focus states", () => {
    expect(
      formatWeeklyFocus({
        brainRoot: "/tmp/Brain",
        weeklyNotePath: "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
        todos: [],
        waiting: [],
        capturedCount: 1,
      })
    ).toBe(
      [
        "Weekly note: /tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
        "Now: (none)",
        "Next: (none)",
        "Waiting: (none)",
        "Captured: 1 unchecked item",
      ].join("\n")
    )
  })

  test("formats a focus card capped by the supplied focus model", () => {
    expect(
      formatWeeklyFocusCard({
        brainRoot: "/tmp/Brain",
        weeklyNotePath: "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
        now: "One",
        next: "Two",
        todos: ["One", "Two", "Three", "Four", "Five"],
        waiting: ["Waiting on review"],
        capturedCount: 3,
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
        "Captured: 3 unchecked items",
        "",
        "Source: /tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
      ].join("\n")
    )
  })

  test("builds Copilot prompts for selected TODOs", () => {
    const prompt = buildWeeklyTodoPrompt("Ship the current PR")

    expect(prompt).toContain("I want to work on this weekly note TODO item")
    expect(prompt).toContain("Ship the current PR")
    expect(prompt).toContain("weekly note as the canonical commitment store")
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
