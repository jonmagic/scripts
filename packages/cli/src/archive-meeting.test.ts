import { afterEach, describe, expect, test } from "bun:test"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"
import { checkOffWeeklyNote, replacePendingPlaceholders } from "./archive-meeting.js"

const tempDirs: string[] = []

function createBrain(content: string): { brainDir: string; weeklyNotePath: string } {
  const brainDir = fs.mkdtempSync(path.join(os.tmpdir(), "archive-meeting-"))
  tempDirs.push(brainDir)

  const weeklyNotesDir = path.join(brainDir, "Weekly Notes")
  fs.mkdirSync(weeklyNotesDir, { recursive: true })

  const weeklyNotePath = path.join(weeklyNotesDir, "Week of 2026-06-01.md")
  fs.writeFileSync(weeklyNotePath, content, "utf-8")

  return { brainDir, weeklyNotePath }
}

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

describe("archive meeting weekly note updates", () => {
  test("replaces only the next pending placeholder for recurring meetings", () => {
    const { brainDir, weeklyNotePath } = createBrain([
      "- [ ] 2026 [[Meeting Notes/team-sync]] {{Meeting Notes/team-sync}}",
      "- [ ] 2026 [[Meeting Notes/team-sync]] {{Meeting Notes/team-sync}}",
      "- [ ] 2026 [[Meeting Notes/other]] {{Meeting Notes/other}}",
      "",
    ].join("\n"))

    const result = replacePendingPlaceholders(
      brainDir,
      "team-sync",
      "2026-06-02",
      "01"
    )

    expect(result).toBe("Replaced 1 placeholder in Week of 2026-06-01.md")
    expect(fs.readFileSync(weeklyNotePath, "utf-8")).toBe([
      "- [ ] 2026 [[Meeting Notes/team-sync]] [[Meeting Notes/team-sync/2026-06-02/01]]",
      "- [ ] 2026 [[Meeting Notes/team-sync]] {{Meeting Notes/team-sync}}",
      "- [ ] 2026 [[Meeting Notes/other]] {{Meeting Notes/other}}",
      "",
    ].join("\n"))
  })

  test("checks off only the next unchecked recurring meeting item", () => {
    const { brainDir, weeklyNotePath } = createBrain([
      "- [ ] 2026 [[Meeting Notes/team-sync]] {{Meeting Notes/team-sync}}",
      "- [ ] 2026 [[Meeting Notes/team-sync]] {{Meeting Notes/team-sync}}",
      "- [ ] 2026 [[Meeting Notes/other]] {{Meeting Notes/other}}",
      "",
    ].join("\n"))

    const result = checkOffWeeklyNote(brainDir, "team-sync", "2026-06-02")

    expect(result).toBe("Checked off 1 item in Week of 2026-06-01.md")
    expect(fs.readFileSync(weeklyNotePath, "utf-8")).toBe([
      "- [x] 2026 [[Meeting Notes/team-sync]] {{Meeting Notes/team-sync}}",
      "- [ ] 2026 [[Meeting Notes/team-sync]] {{Meeting Notes/team-sync}}",
      "- [ ] 2026 [[Meeting Notes/other]] {{Meeting Notes/other}}",
      "",
    ].join("\n"))
  })
})
