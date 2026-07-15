import { afterEach, describe, expect, test } from "bun:test"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"
import {
  buildCommitmentCaptureArgs,
  checkOffWeeklyNote,
  convertVttToMarkdown,
  defaultCommitmentCaptureRunnerPath,
  findNextNumber,
  replacePendingPlaceholders,
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

describe("archive meeting commitment capture hook", () => {
  test("builds a scoped post-meeting runner command", () => {
    const args = buildCommitmentCaptureArgs({
      brainDir: "/Users/jonmagic/Brain",
      meetingNotePath: "/Users/jonmagic/Brain/Meeting Notes/team/2026-07-08/01.md",
      transcriptPath: "/Users/jonmagic/Brain/Transcripts/2026-07-08/01.md",
    })

    expect(defaultCommitmentCaptureRunnerPath()).toContain(
      ".copilot/skills/commitment-capture/scripts/commitment-capture-run"
    )
    expect(args).toEqual([
      "--mode",
      "meeting",
      "--brain-path",
      "/Users/jonmagic/Brain",
      "--meeting-note",
      "/Users/jonmagic/Brain/Meeting Notes/team/2026-07-08/01.md",
      "--transcript",
      "/Users/jonmagic/Brain/Transcripts/2026-07-08/01.md",
    ])
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
