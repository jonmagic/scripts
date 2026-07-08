import { describe, expect, test } from "bun:test"

import { formatWeeklyFocus } from "./weekly-note-commitments.js"

describe("weekly note commitment CLI helpers", () => {
  test("formats a sparse weekly focus view", () => {
    expect(
      formatWeeklyFocus({
        brainRoot: "/tmp/Brain",
        weeklyNotePath: "/tmp/Brain/Weekly Notes/Week of 2026-07-05.md",
        now: "Ship the current PR",
        next: "Write the follow-up ask",
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
})
