import { afterEach, describe, expect, test } from "bun:test"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"
import {
  buildBrainTasksAddArgs,
  buildTaskReviewBuffer,
  checkOffWeeklyNote,
  convertVttToMarkdown,
  defaultBrainTasksPath,
  findNextNumber,
  parseTaskCandidates,
  parseTaskReviewBuffer,
  replacePendingPlaceholders,
  resolveEditor,
} from "./archive-meeting.js"

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

describe("archive meeting task capture", () => {
  test("strips the formatting models add despite being asked not to", () => {
    const raw = [
      "```",
      "- Send the migration timeline to @octocat",
      "1. Draft the rollout plan for the new detector",
      "- [ ] Review the audit findings",
      "",
      "```",
    ].join("\n")

    expect(parseTaskCandidates(raw)).toEqual([
      "Send the migration timeline to @octocat",
      "Draft the rollout plan for the new detector",
      "Review the audit findings",
    ])
  })

  test("drops duplicates, empty answers, and prose", () => {
    const raw = [
      "Send the timeline to @octocat",
      "send the timeline to @octocat",
      "None",
      "x".repeat(400),
    ].join("\n")

    expect(parseTaskCandidates(raw)).toEqual(["Send the timeline to @octocat"])
  })

  test("round trips a review buffer, ignoring the instructions", () => {
    const tasks = ["Send the timeline to @octocat", "Review the audit findings"]
    const buffer = buildTaskReviewBuffer(tasks)

    expect(buffer).toContain("# One task per line.")
    expect(parseTaskReviewBuffer(buffer)).toEqual(tasks)
  })

  test("treats an emptied buffer as a decision to skip", () => {
    expect(parseTaskReviewBuffer(buildTaskReviewBuffer([]))).toEqual([])
  })

  test("keeps tasks the reviewer typed by hand", () => {
    const buffer = `${buildTaskReviewBuffer(["Send the timeline to @octocat"])}Book the follow up with @mona\n`

    expect(parseTaskReviewBuffer(buffer)).toEqual([
      "Send the timeline to @octocat",
      "Book the follow up with @mona",
    ])
  })

  test("prefers VISUAL and splits editor arguments", () => {
    expect(resolveEditor({ VISUAL: "code --wait", EDITOR: "vi" })).toEqual([
      "code",
      "--wait",
    ])
    expect(resolveEditor({ EDITOR: "nvim" })).toEqual(["nvim"])
    expect(resolveEditor({})).toEqual(["vi"])
  })

  test("adds board tasks into the current week so Weekly Focus can see them", () => {
    expect(
      buildBrainTasksAddArgs({
        title: "Send the timeline to @octocat",
        source: "[[Meeting Notes/example/2026-07-08/01]]",
      })
    ).toEqual([
      "add",
      "--title",
      "Send the timeline to @octocat",
      "--status",
      "Todo",
      "--week",
      "current",
      "--source",
      "[[Meeting Notes/example/2026-07-08/01]]",
    ])
    expect(defaultBrainTasksPath()).toContain(".copilot/skills/brain/scripts/brain-tasks")
  })
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

describe("archive meeting transcript preparation", () => {
  test("removes VTT voice tags from single-line and continued cues", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "archive-meeting-vtt-"))
    tempDirs.push(tempDir)
    const vttPath = path.join(tempDir, "meeting.vtt")
    fs.writeFileSync(vttPath, [
      "WEBVTT",
      "",
      "00:00:01.000 --> 00:00:03.000",
      "<v Jonathan Hoyt>Hello there,</v>",
      "",
      "00:00:03.000 --> 00:00:05.000",
      "<v Jonathan Hoyt>continued thought</v>",
      "without another opening tag</v>",
      "",
    ].join("\n"))

    expect(convertVttToMarkdown(vttPath)).toBe([
      "- [00:00:01] Jonathan Hoyt: Hello there,",
      "- [00:00:03] Jonathan Hoyt: continued thought without another opening tag",
      "",
    ].join("\n"))
  })

  test("allocates after existing meeting notes for the target", () => {
    const brainDir = fs.mkdtempSync(path.join(os.tmpdir(), "archive-meeting-number-"))
    tempDirs.push(brainDir)
    const meetingNotesDir = path.join(
      brainDir,
      "Meeting Notes",
      "Copilot",
      "2026-07-15"
    )
    fs.mkdirSync(meetingNotesDir, { recursive: true })
    fs.writeFileSync(path.join(meetingNotesDir, "01.md"), "existing")

    expect(findNextNumber(brainDir, "2026-07-15", "Copilot")).toBe(2)
  })
})
