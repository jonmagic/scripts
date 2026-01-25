/**
 * Archive Meeting
 *
 * Archives a single meeting by:
 * 1. Processing input (VTT file or Zoom folder) into markdown transcript
 * 2. Adding frontmatter with uid, type, created
 * 3. Generating executive summary using copilot CLI
 * 4. Generating detailed meeting notes using copilot CLI
 * 5. Updating the appropriate Meeting Notes file
 * 6. Checking off the meeting in Weekly Notes (if found)
 *
 * This mirrors the Ruby archive_single_meeting.rb script from the skill.
 */

import * as fs from "node:fs"
import * as path from "node:path"
import { spawn } from "node:child_process"
import {
  generateTid,
  serializeFrontmatter,
  type FrontmatterData,
} from "@jonmagic/scripts-core"

export interface ArchiveMeetingOptions {
  brainDir: string
  input?: string
  meetingNotesTarget?: string
  date?: string
  executiveSummaryPromptPath: string
  detailedNotesPromptPath: string
  dryRun?: boolean
}

export interface ListRecentMeetingsOptions {
  zoomDir?: string
  downloadsDir?: string
  limit?: number
  merge?: boolean
}

export interface MeetingCandidate {
  type: "zoom" | "teams_vtt"
  path: string
  mtimeIso: string
  date: string
  hint: string
}

/**
 * Run fzf to select from a list of options
 */
async function fzfSelect(
  options: string[],
  prompt: string
): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn("fzf", ["--prompt", prompt], {
      stdio: ["pipe", "pipe", "inherit"],
    })

    let result = ""

    proc.stdout.on("data", (data: Buffer) => {
      result += data.toString()
    })

    proc.on("close", (code) => {
      if (code === 0) {
        resolve(result.trim())
      } else {
        reject(new Error("fzf selection cancelled"))
      }
    })

    proc.stdin.write(options.join("\n"))
    proc.stdin.end()
  })
}

/**
 * Select a meeting input interactively using fzf
 */
export async function selectMeetingInput(
  options: ListRecentMeetingsOptions = {}
): Promise<string> {
  const meetings = listRecentMeetings({ ...options, merge: true }) as MeetingCandidate[]

  if (meetings.length === 0) {
    throw new Error("No recent meetings found")
  }

  // Format options for display: "date | type | hint"
  const displayOptions = meetings.map(
    (m) => `${m.date} | ${m.type.padEnd(9)} | ${m.hint}`
  )

  const selection = await fzfSelect(displayOptions, "Select meeting: ")

  // Find the matching meeting
  const idx = displayOptions.indexOf(selection)
  if (idx === -1) {
    throw new Error("Selection not found")
  }

  return meetings[idx]!.path
}

/**
 * Find the latest weekly notes file
 */
function findLatestWeeklyNotes(brainDir: string): string | null {
  const weeklyNotesDir = path.join(brainDir, "Weekly Notes")
  if (!fs.existsSync(weeklyNotesDir)) return null

  const weeklyNoteRe = /^Week of (\d{4}-\d{2}-\d{2})\.md$/
  const files: { date: string; path: string }[] = []

  for (const entry of fs.readdirSync(weeklyNotesDir)) {
    const match = weeklyNoteRe.exec(entry)
    if (match) {
      files.push({
        date: match[1]!,
        path: path.join(weeklyNotesDir, entry),
      })
    }
  }

  if (files.length === 0) return null

  files.sort((a, b) => b.date.localeCompare(a.date))
  return files[0]!.path
}

/**
 * Extract meeting note entries from weekly notes (full paths with dates)
 */
function extractMeetingEntries(weeklyNotesPath: string): { display: string; target: string }[] {
  const content = fs.readFileSync(weeklyNotesPath, "utf-8")

  // Match wikilinks like [[Meeting Notes/briangreenhill/2026-01-20/01]]
  // Extract full path after "Meeting Notes/"
  const wikiLinkRe = /\[\[Meeting Notes\/([^\]]+)\]\]/g
  const entries: { display: string; target: string }[] = []
  const seen = new Set<string>()

  let match
  while ((match = wikiLinkRe.exec(content)) !== null) {
    const fullPath = match[1]!
    if (seen.has(fullPath)) continue
    seen.add(fullPath)

    // Extract target name (first path segment)
    const target = fullPath.split("/")[0]!
    entries.push({ display: fullPath, target })
  }

  // Sort by date (second segment) descending, then by target
  return entries.sort((a, b) => {
    const dateA = a.display.split("/")[1] || ""
    const dateB = b.display.split("/")[1] || ""
    if (dateB !== dateA) return dateB.localeCompare(dateA)
    return a.target.localeCompare(b.target)
  })
}

/**
 * Select a meeting notes target interactively using fzf
 */
export async function selectMeetingNotesTarget(
  brainDir: string
): Promise<string> {
  const weeklyNotesPath = findLatestWeeklyNotes(brainDir)

  if (!weeklyNotesPath) {
    throw new Error("No weekly notes found")
  }

  const entries = extractMeetingEntries(weeklyNotesPath)

  if (entries.length === 0) {
    throw new Error("No meeting note targets found in weekly notes")
  }

  console.log(`Found ${entries.length} meetings in ${path.basename(weeklyNotesPath)}`)

  const displayOptions = entries.map((e) => e.display)
  const selection = await fzfSelect(displayOptions, "Select meeting: ")

  // Find the matching entry and return just the target name
  const entry = entries.find((e) => e.display === selection)
  if (!entry) {
    throw new Error("Selection not found")
  }

  return entry.target
}

/**
 * Run a command and return its output
 */
async function runCommand(
  cmd: string,
  args: string[],
  input?: string
): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, {
      stdio: ["pipe", "pipe", "pipe"],
    })

    let stdout = ""
    let stderr = ""

    proc.stdout.on("data", (data: Buffer) => {
      stdout += data.toString()
    })

    proc.stderr.on("data", (data: Buffer) => {
      stderr += data.toString()
    })

    proc.on("close", (code) => {
      if (code === 0) {
        resolve(stdout)
      } else {
        reject(new Error(`Command failed with code ${code}: ${stderr}`))
      }
    })

    if (input) {
      proc.stdin.write(input)
      proc.stdin.end()
    } else {
      proc.stdin.end()
    }
  })
}

/**
 * Get existing file numbers in a directory (e.g., 01.md, 02.md)
 */
function getExistingNumbers(directory: string): Set<number> {
  const numbers = new Set<number>()
  if (!fs.existsSync(directory)) return numbers

  for (const file of fs.readdirSync(directory)) {
    const match = file.match(/^(\d+)\.md$/)
    if (match) {
      numbers.add(parseInt(match[1]!, 10))
    }
  }
  return numbers
}

/**
 * Find next available file number across Transcripts and Executive Summaries
 */
function findNextNumber(brainDir: string, date: string): number {
  const transcriptsDir = path.join(brainDir, "Transcripts", date)
  const execSummariesDir = path.join(brainDir, "Executive Summaries", date)

  const transcriptNums = getExistingNumbers(transcriptsDir)
  const execSummaryNums = getExistingNumbers(execSummariesDir)

  const allNums = new Set([...transcriptNums, ...execSummaryNums])
  if (allNums.size === 0) return 1

  return Math.max(...allNums) + 1
}

/**
 * Get date from file mtime
 */
function getDateFromFile(filePath: string): string {
  const stat = fs.statSync(filePath)
  return stat.mtime.toISOString().slice(0, 10)
}

/**
 * Convert VTT to markdown
 */
function convertVttToMarkdown(vttPath: string): string {
  const vttText = fs.readFileSync(vttPath, "utf-8")
  const lines = vttText.split("\n")
  const out: string[] = []

  const cueRe = /^(\d{2}:\d{2}:\d{2})(?:\.\d{3})?\s+-->\s+\d{2}:\d{2}:\d{2}/
  const voiceTagRe = /<v\s+([^>]+)>(.*)(?:<\/v>)?/

  let i = 0
  while (i < lines.length) {
    const line = lines[i]!.trim()

    // Skip headers and blank lines
    if (!line || line.toUpperCase().startsWith("WEBVTT") || line.startsWith("NOTE")) {
      i++
      continue
    }

    const cueMatch = cueRe.exec(line)
    if (!cueMatch) {
      i++
      continue
    }

    const start = cueMatch[1]!

    // Consume cue payload lines until blank
    i++
    const payload: string[] = []
    while (i < lines.length && lines[i]!.trim()) {
      payload.push(lines[i]!.trim())
      i++
    }

    let speaker: string | null = null
    const textParts: string[] = []

    for (const p of payload) {
      const voiceMatch = voiceTagRe.exec(p)
      if (voiceMatch) {
        speaker = voiceMatch[1]!.trim()
        const text = voiceMatch[2]!.replace(/<\/v>/, "").trim()
        if (text) textParts.push(text)
      } else if (p.includes(":") && p.split(":")[0]!.length <= 60) {
        const [maybeSpeaker, ...rest] = p.split(":")
        const restText = rest.join(":").trim()
        if (maybeSpeaker && restText) {
          speaker = speaker || maybeSpeaker.trim()
          textParts.push(restText)
        } else {
          textParts.push(p)
        }
      } else {
        textParts.push(p)
      }
    }

    const text = textParts.filter(Boolean).join(" ").trim()
    if (!text) {
      i++
      continue
    }

    if (speaker) {
      out.push(`- [${start}] ${speaker}: ${text}`)
    } else {
      out.push(`- [${start}] ${text}`)
    }
    i++
  }

  return out.join("\n") + "\n"
}

/**
 * Process Zoom folder into markdown
 */
function processZoomFolder(zoomPath: string): string {
  const parts: string[] = []
  const patterns = ["*.vtt", "*.txt"]

  for (const pattern of patterns) {
    const ext = pattern.slice(1) // .vtt or .txt
    const files = fs
      .readdirSync(zoomPath)
      .filter((f) => f.toLowerCase().endsWith(ext) && !f.startsWith("."))
      .sort()

    for (const file of files) {
      const filePath = path.join(zoomPath, file)
      let content = fs.readFileSync(filePath, "utf-8")

      // If it's a VTT, convert it
      if (file.toLowerCase().endsWith(".vtt")) {
        content = convertVttToMarkdown(filePath)
      }

      parts.push(`<!-- START: ${file} -->\n${content}\n<!-- END: ${file} -->`)
    }
  }

  if (parts.length === 0) {
    throw new Error(`No transcript files found in ${zoomPath}`)
  }

  return parts.join("\n\n")
}

/**
 * Call copilot CLI with a system prompt and input
 */
async function callCopilot(
  transcript: string,
  promptPath: string
): Promise<string> {
  if (!fs.existsSync(promptPath)) {
    throw new Error(`Prompt file not found: ${promptPath}`)
  }

  const systemPrompt = fs.readFileSync(promptPath, "utf-8")
  const fullPrompt = `${systemPrompt}\n\n${transcript}`

  const result = await runCommand("copilot", ["-p", fullPrompt, "--allow-all-tools"])
  return result.trim()
}

/**
 * Create frontmatter for a file
 */
function createFrontmatter(type: string, date: string): string {
  const fm: FrontmatterData = {
    uid: generateTid(),
    type,
    created: `${date}T00:00:00.000Z`,
  }
  return serializeFrontmatter(fm)
}

/**
 * Ensure bullets format for notes
 */
function ensureBullets(text: string): string {
  return text
    .split("\n")
    .map((ln) => ln.trimEnd())
    .filter((ln) => ln)
    .map((ln) => (ln.trimStart().startsWith("-") ? ln : `- ${ln.trim()}`))
    .join("\n")
}

/**
 * Update Meeting Notes file
 */
function updateMeetingNotes(options: {
  brainDir: string
  target: string
  date: string
  transcriptLink: string
  summaryLink: string
  detailedNotes: string
}): string {
  const { brainDir, target, date, transcriptLink, summaryLink, detailedNotes } =
    options

  const meetingNotesFile = path.join(brainDir, "Meeting Notes", `${target}.md`)
  const header = `## ${date}`

  const detailed = ensureBullets(detailedNotes)
  let block = `- ${transcriptLink}\n- ${summaryLink}\n`
  if (detailed) block += `${detailed}\n`
  block += "\n"

  if (!fs.existsSync(meetingNotesFile)) {
    fs.mkdirSync(path.dirname(meetingNotesFile), { recursive: true })
    fs.writeFileSync(meetingNotesFile, `${header}\n\n${block}`, "utf-8")
    return `Created: ${meetingNotesFile}`
  }

  let text = fs.readFileSync(meetingNotesFile, "utf-8")

  // Find all date headers
  const dateHeaderRe = /^##\s+(\d{4}-\d{2}-\d{2})\s*$/gm
  const matches: { date: string; start: number }[] = []
  let match
  while ((match = dateHeaderRe.exec(text)) !== null) {
    matches.push({ date: match[1]!, start: match.index })
  }

  const targetIdx = matches.findIndex((m) => m.date === date)

  if (targetIdx === -1) {
    // Prepend new section
    text = `${header}\n\n${block}${text}`
  } else {
    // Insert at end of target section (before next header or end)
    const nextHeaderStart =
      targetIdx + 1 < matches.length ? matches[targetIdx + 1]!.start : text.length

    const before = text.slice(0, nextHeaderStart)
    const after = text.slice(nextHeaderStart)

    const beforeWithNewline = before.endsWith("\n") ? before : before + "\n"
    text = beforeWithNewline + block + after
  }

  fs.writeFileSync(meetingNotesFile, text, "utf-8")
  return `Updated: ${meetingNotesFile}`
}

/**
 * Check off meeting in Weekly Notes
 */
function checkOffWeeklyNote(
  brainDir: string,
  target: string,
  meetingDate: string
): string {
  const weeklyNotesDir = path.join(brainDir, "Weekly Notes")
  if (!fs.existsSync(weeklyNotesDir)) {
    return "Weekly Notes directory not found"
  }

  const meetingDt = new Date(meetingDate)
  const weeklyNoteRe = /^Week of (\d{4}-\d{2}-\d{2})\.md$/

  const candidates: { weekStart: Date; path: string }[] = []
  for (const entry of fs.readdirSync(weeklyNotesDir)) {
    const match = weeklyNoteRe.exec(entry)
    if (match) {
      candidates.push({
        weekStart: new Date(match[1]!),
        path: path.join(weeklyNotesDir, entry),
      })
    }
  }

  if (candidates.length === 0) {
    return "No Weekly Notes found"
  }

  candidates.sort((a, b) => b.weekStart.getTime() - a.weekStart.getTime())

  let weeklyNote: string | null = null
  for (const { weekStart, path: notePath } of candidates) {
    const weekEnd = new Date(weekStart)
    weekEnd.setDate(weekEnd.getDate() + 6)
    if (meetingDt >= weekStart && meetingDt <= weekEnd) {
      weeklyNote = notePath
      break
    }
  }

  if (!weeklyNote) {
    return `No Weekly Note found containing date ${meetingDate}`
  }

  let content = fs.readFileSync(weeklyNote, "utf-8")
  const escapedTarget = target.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  const pattern = new RegExp(
    `^(\\s*- \\[) (\\] \\d{4} \\[\\[Meeting Notes\\/${escapedTarget}(?:\\|[^\\]]+)?\\]\\].*?)$`,
    "gim"
  )

  let count = 0
  content = content.replace(pattern, (_, prefix, suffix) => {
    count++
    return `${prefix}x${suffix}`
  })

  if (count > 0) {
    fs.writeFileSync(weeklyNote, content, "utf-8")
    return `Checked off ${count} item(s) in ${path.basename(weeklyNote)}`
  }

  return `No matching checklist item found in ${path.basename(weeklyNote)}`
}

/**
 * List recent Zoom folders
 */
function listZoomFolders(zoomDir: string, limit: number): MeetingCandidate[] {
  if (!fs.existsSync(zoomDir)) return []

  const candidates: MeetingCandidate[] = []
  for (const entry of fs.readdirSync(zoomDir)) {
    if (entry.startsWith(".")) continue
    const entryPath = path.join(zoomDir, entry)
    const stat = fs.statSync(entryPath)
    if (stat.isDirectory()) {
      candidates.push({
        type: "zoom",
        path: entryPath,
        mtimeIso: stat.mtime.toISOString(),
        date: stat.mtime.toISOString().slice(0, 10),
        hint: entry,
      })
    }
  }

  return candidates
    .sort((a, b) => b.mtimeIso.localeCompare(a.mtimeIso))
    .slice(0, limit)
}

/**
 * List recent Teams VTT files
 */
function listTeamsVtts(downloadsDir: string, limit: number): MeetingCandidate[] {
  if (!fs.existsSync(downloadsDir)) return []

  const candidates: MeetingCandidate[] = []
  for (const entry of fs.readdirSync(downloadsDir)) {
    if (entry.startsWith(".") || !entry.toLowerCase().endsWith(".vtt")) continue
    const entryPath = path.join(downloadsDir, entry)
    const stat = fs.statSync(entryPath)
    if (stat.isFile()) {
      candidates.push({
        type: "teams_vtt",
        path: entryPath,
        mtimeIso: stat.mtime.toISOString(),
        date: stat.mtime.toISOString().slice(0, 10),
        hint: entry,
      })
    }
  }

  return candidates
    .sort((a, b) => b.mtimeIso.localeCompare(a.mtimeIso))
    .slice(0, limit)
}

/**
 * List recent meetings from Zoom and Teams
 */
export function listRecentMeetings(
  options: ListRecentMeetingsOptions = {}
): { zoom: MeetingCandidate[]; teams_vtt: MeetingCandidate[] } | MeetingCandidate[] {
  const zoomDir = options.zoomDir || path.join(process.env.HOME || "", "Documents/Zoom")
  const downloadsDir = options.downloadsDir || path.join(process.env.HOME || "", "Downloads")
  const limit = options.limit || 10

  const zoom = listZoomFolders(zoomDir, limit)
  const teams = listTeamsVtts(downloadsDir, limit)

  if (options.merge) {
    return [...zoom, ...teams].sort((a, b) => b.mtimeIso.localeCompare(a.mtimeIso))
  }

  return { zoom, teams_vtt: teams }
}

/**
 * Main archive meeting function
 */
export async function archiveMeeting(
  options: ArchiveMeetingOptions
): Promise<void> {
  const {
    brainDir,
    executiveSummaryPromptPath,
    detailedNotesPromptPath,
    dryRun = false,
  } = options

  if (!fs.existsSync(brainDir)) {
    throw new Error(`Brain directory does not exist: ${brainDir}`)
  }

  // Select input interactively if not provided
  let input = options.input
  if (!input) {
    console.log("No input specified, selecting from recent meetings...")
    input = await selectMeetingInput()
  }

  if (!fs.existsSync(input)) {
    throw new Error(`Input path does not exist: ${input}`)
  }

  // Select target interactively if not provided
  let meetingNotesTarget = options.meetingNotesTarget
  if (!meetingNotesTarget) {
    console.log("No target specified, selecting from weekly notes...")
    meetingNotesTarget = await selectMeetingNotesTarget(brainDir)
  }

  // Determine date
  let meetingDate: string
  if (options.date) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(options.date)) {
      throw new Error(`Invalid date format '${options.date}', expected YYYY-MM-DD`)
    }
    meetingDate = options.date
  } else {
    meetingDate = getDateFromFile(input)
  }

  console.log(`Processing: ${input}`)
  console.log(`Date: ${meetingDate}`)
  console.log(`Target: Meeting Notes/${meetingNotesTarget}.md`)

  // Step 1: Get next file number
  const nextNum = findNextNumber(brainDir, meetingDate)
  const nextNumStr = nextNum.toString().padStart(2, "0")
  console.log(`File number: ${nextNumStr}`)

  const transcriptsDir = path.join(brainDir, "Transcripts", meetingDate)
  const execSummariesDir = path.join(brainDir, "Executive Summaries", meetingDate)
  const transcriptPath = path.join(transcriptsDir, `${nextNumStr}.md`)
  const execSummaryPath = path.join(execSummariesDir, `${nextNumStr}.md`)

  if (dryRun) {
    console.log("\n[DRY RUN] Would create:")
    console.log(`  - ${transcriptPath}`)
    console.log(`  - ${execSummaryPath}`)
    console.log(`  - Update Meeting Notes/${meetingNotesTarget}.md`)
    return
  }

  // Step 2: Convert input to markdown transcript
  console.log("\nConverting transcript...")
  let transcriptMd: string
  const stat = fs.statSync(input)
  if (stat.isDirectory()) {
    transcriptMd = processZoomFolder(input)
  } else if (input.toLowerCase().endsWith(".vtt")) {
    transcriptMd = convertVttToMarkdown(input)
  } else {
    transcriptMd = fs.readFileSync(input, "utf-8")
  }

  // Step 3: Write transcript with frontmatter
  fs.mkdirSync(transcriptsDir, { recursive: true })
  const transcriptFrontmatter = createFrontmatter("transcript", meetingDate)
  fs.writeFileSync(
    transcriptPath,
    `${transcriptFrontmatter}\n\n${transcriptMd}`,
    "utf-8"
  )
  console.log(`Created: ${transcriptPath}`)

  // Step 4: Generate executive summary via copilot
  console.log("\nGenerating executive summary...")
  const execSummary = await callCopilot(transcriptMd, executiveSummaryPromptPath)

  fs.mkdirSync(execSummariesDir, { recursive: true })
  const summaryFrontmatter = createFrontmatter("executive.summary", meetingDate)
  fs.writeFileSync(
    execSummaryPath,
    `${summaryFrontmatter}\n\n${execSummary}\n`,
    "utf-8"
  )
  console.log(`Created: ${execSummaryPath}`)

  // Step 5: Generate meeting notes via copilot
  console.log("\nGenerating meeting notes...")
  const meetingNotes = await callCopilot(transcriptMd, detailedNotesPromptPath)

  // Step 6: Update meeting notes file
  console.log("\nUpdating meeting notes...")
  const transcriptLink = `[[Transcripts/${meetingDate}/${nextNumStr}|Transcript]]`
  const summaryLink = `[[Executive Summaries/${meetingDate}/${nextNumStr}|Executive Summary]]`

  const result = updateMeetingNotes({
    brainDir,
    target: meetingNotesTarget,
    date: meetingDate,
    transcriptLink,
    summaryLink,
    detailedNotes: meetingNotes,
  })
  console.log(result)

  // Step 7: Check off in weekly notes
  const weeklyResult = checkOffWeeklyNote(brainDir, meetingNotesTarget, meetingDate)
  if (weeklyResult) {
    console.log(`\n${weeklyResult}`)
  }

  // Output summary
  console.log("\n" + "=".repeat(60))
  console.log("Archive complete!")
  console.log(`  Transcript:        ${transcriptPath}`)
  console.log(`  Executive Summary: ${execSummaryPath}`)
  console.log(`  Meeting Notes:     Meeting Notes/${meetingNotesTarget}.md`)
}
