/**
 * Archive Meeting
 *
 * Archives a meeting by:
 * 1. Ensuring required subfolders exist in your notes directory
 * 2. Prompting to select a meeting folder
 * 3. Finding transcript and chat log files
 * 4. Combining files into a single transcript
 * 5. Generating an executive summary using LLM
 * 6. Generating detailed meeting notes using LLM
 * 7. Updating the appropriate Meeting Notes file
 */

import * as fs from "node:fs"
import * as path from "node:path"
import { spawn } from "node:child_process"

export interface ArchiveMeetingOptions {
  transcriptsDir: string
  targetDir: string
  executiveSummaryPromptPath: string
  detailedNotesPromptPath: string
  llmModel?: string
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
    }
  })
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
 * Select a folder from the transcripts directory using fzf
 */
async function selectMeetingFolder(transcriptsDir: string): Promise<string> {
  const folders = fs
    .readdirSync(transcriptsDir)
    .filter((f) => fs.statSync(path.join(transcriptsDir, f)).isDirectory())
    .sort()
    .reverse()

  if (folders.length === 0) {
    throw new Error(`No folders found in ${transcriptsDir}`)
  }

  const selection = await fzfSelect(folders, "Select meeting folder: ")
  return path.join(transcriptsDir, selection)
}

/**
 * Ensure required subfolders exist
 */
function ensureSubfolders(targetDir: string): void {
  const subfolders = ["Executive Summaries", "Meeting Notes", "Transcripts"]
  for (const subfolder of subfolders) {
    const dirPath = path.join(targetDir, subfolder)
    if (!fs.existsSync(dirPath)) {
      fs.mkdirSync(dirPath, { recursive: true })
    }
  }
}

/**
 * Find transcript files in a folder
 */
function findTranscriptFiles(folder: string): string[] {
  return fs
    .readdirSync(folder)
    .filter((f) => f.endsWith(".txt") || f.endsWith(".vtt"))
    .map((f) => path.join(folder, f))
}

/**
 * Get the next available transcript filename
 */
function nextTranscriptFilename(destDir: string): string {
  const existing = fs
    .readdirSync(destDir)
    .filter((f) => /^\d{2}\.md$/.test(f))
    .map((f) => parseInt(f.slice(0, 2), 10))

  const nextNum = (Math.max(0, ...existing) || 0) + 1
  return `${nextNum.toString().padStart(2, "0")}.md`
}

/**
 * Write combined transcript file
 */
function writeCombinedTranscript(
  destFile: string,
  transcriptFiles: string[]
): void {
  let content = ""
  for (const file of transcriptFiles) {
    const basename = path.basename(file)
    const fileContent = fs.readFileSync(file, "utf-8")
    content += `===== START: ${basename} =====\n`
    content += fileContent
    content += `\n===== END: ${basename} =====\n\n`
  }
  fs.writeFileSync(destFile, content)
}

/**
 * Get LLM model flag
 */
function llmModelFlag(llmModel?: string): string[] {
  if (llmModel && llmModel.trim()) {
    return ["-m", llmModel]
  }
  return []
}

/**
 * Generate executive summary using LLM
 */
async function generateExecutiveSummary(
  transcriptFile: string,
  summaryFile: string,
  promptPath: string,
  llmModel?: string
): Promise<void> {
  const transcript = fs.readFileSync(transcriptFile, "utf-8")
  const modelFlag = llmModelFlag(llmModel)
  const args = [...modelFlag, "-f", promptPath]

  console.log("Generating executive summary with llm...")
  const summary = await runCommand("llm", args, transcript)
  fs.writeFileSync(summaryFile, summary)
  console.log(`Executive summary saved to: ${summaryFile}`)
}

/**
 * Generate detailed notes using LLM
 */
async function generateDetailedNotes(
  transcriptFile: string,
  promptPath: string,
  llmModel?: string
): Promise<string> {
  const transcript = fs.readFileSync(transcriptFile, "utf-8")
  const modelFlag = llmModelFlag(llmModel)
  const args = [...modelFlag, "-f", promptPath]

  console.log("Generating detailed notes with llm...")
  return await runCommand("llm", args, transcript)
}

/**
 * Find latest weekly notes file
 */
function findLatestWeeklyNotes(targetDir: string): string {
  const weeklyNotesDir = path.join(targetDir, "Weekly Notes")
  const files = fs
    .readdirSync(weeklyNotesDir)
    .filter((f) => f.startsWith("Week of ") && f.endsWith(".md"))
    .sort()

  if (files.length === 0) {
    throw new Error(`No weekly notes files found in ${weeklyNotesDir}`)
  }

  const latest = files[files.length - 1]
  console.log(`Latest weekly notes file: ${path.join(weeklyNotesDir, latest)}`)
  return path.join(weeklyNotesDir, latest)
}

/**
 * Select meeting notes section using LLM and fzf
 */
async function selectMeetingNotesSection(
  weeklyNotesFile: string,
  executiveSummary: string,
  llmModel?: string
): Promise<string> {
  const content = fs.readFileSync(weeklyNotesFile, "utf-8")

  // Extract Schedule section
  const scheduleMatch = content.match(/^## Schedule\n([\s\S]*?)(?=^## |$)/m)
  if (!scheduleMatch?.[1]) {
    throw new Error("Could not find '## Schedule' section in Weekly Notes")
  }

  const options = scheduleMatch[1]
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"))

  if (options.length === 0) {
    throw new Error("No entries found in '## Schedule' section")
  }

  // Use LLM to sort options by relevance
  const prompt = `Given the following list of people or groups from my schedule and the executive summary of a meeting, sort the list from most likely to least likely to be the correct person or group to attach this transcript to. Do not remove or filter any options. Output only the sorted list, one per line, with no extra commentary.

SCHEDULE OPTIONS:
${options.join("\n")}

EXECUTIVE SUMMARY:
${executiveSummary}`

  const modelFlag = llmModelFlag(llmModel)
  console.log("Suggesting Meeting Notes section with LLM...")
  const sorted = await runCommand("llm", modelFlag, prompt)

  const sortedOptions = sorted
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l)

  const selection = await fzfSelect(
    sortedOptions,
    "Select Meeting Notes group/person: "
  )
  console.log(`You selected: ${selection}`)
  return selection
}

/**
 * Update meeting notes file with links and detailed notes
 */
function updateMeetingNotesFile(options: {
  meetingNotesFile: string
  meetingDate: string
  transcriptLink: string
  summaryLink: string
  detailedNotes: string
}): void {
  const { meetingNotesFile, meetingDate, transcriptLink, summaryLink, detailedNotes } =
    options

  const dateSectionHeader = `## ${meetingDate}`

  // Format detailed notes as list items
  const detailedNotesItems = detailedNotes
    .split("\n")
    .map((l) => l.trimEnd())
    .filter((l) => l)
    .map((l) => (l.trimStart().startsWith("-") ? l : `- ${l}`))
    .join("\n")

  const newContentBlock =
    `- ${transcriptLink}\n- ${summaryLink}\n` +
    (detailedNotesItems ? `${detailedNotesItems}\n` : "") +
    "\n"

  if (fs.existsSync(meetingNotesFile)) {
    let content = fs.readFileSync(meetingNotesFile, "utf-8")

    // Check if date section exists
    if (content.includes(dateSectionHeader)) {
      // Find the section and append to it
      const regex = new RegExp(
        `(${dateSectionHeader.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n)`,
        "g"
      )
      content = content.replace(regex, `$1\n${newContentBlock}`)
    } else {
      // Prepend new section
      content = `${dateSectionHeader}\n\n${newContentBlock}${content}`
    }

    fs.writeFileSync(meetingNotesFile, content)
    console.log(`Updated existing Meeting Notes file: ${meetingNotesFile}`)
  } else {
    // Create new file
    const newContent = `${dateSectionHeader}\n\n${newContentBlock}`
    fs.writeFileSync(meetingNotesFile, newContent)
    console.log(`Created new Meeting Notes file: ${meetingNotesFile}`)
  }
}

/**
 * Extract canonical name from selection
 */
function extractCanonicalName(selection: string): string {
  let cleaned = selection.replace(/^Meeting Notes\//, "")

  // Handle wikilinks
  const wikilinkMatch = cleaned.match(/\[\[(.+?)(?:\|.+?)?\]\]/)
  if (wikilinkMatch?.[1]) {
    return wikilinkMatch[1].replace(/^Meeting Notes\//, "")
  }

  // Fallback: get last word
  return cleaned.trim().split(/\s+/).pop()?.replace(/[^\w-]/g, "") || cleaned
}

/**
 * Main archive meeting function
 */
export async function archiveMeeting(
  options: ArchiveMeetingOptions
): Promise<void> {
  const {
    transcriptsDir,
    targetDir,
    executiveSummaryPromptPath,
    detailedNotesPromptPath,
    llmModel,
  } = options

  // Step 1: Ensure required subfolders exist
  ensureSubfolders(targetDir)

  // Step 2: Select meeting folder
  const selectedFolder = await selectMeetingFolder(transcriptsDir)
  console.log(`Selected meeting folder: ${selectedFolder}`)

  // Step 3: Find transcript files
  const transcriptFiles = findTranscriptFiles(selectedFolder)
  if (transcriptFiles.length === 0) {
    throw new Error(`No transcript files found in ${selectedFolder}`)
  }

  // Step 4: Prepare output directory and file
  const stat = fs.statSync(selectedFolder)
  const meetingDate = stat.mtime.toISOString().slice(0, 10)
  const transcriptsBase = path.join(targetDir, "Transcripts")
  const destDir = path.join(transcriptsBase, meetingDate)
  fs.mkdirSync(destDir, { recursive: true })
  const filename = nextTranscriptFilename(destDir)
  const destFile = path.join(destDir, filename)

  // Step 5: Write combined transcript
  writeCombinedTranscript(destFile, transcriptFiles)
  console.log(`Transcript saved to: ${destFile}`)

  // Step 6: Generate executive summary
  const execSummariesBase = path.join(targetDir, "Executive Summaries")
  const execDir = path.join(execSummariesBase, meetingDate)
  fs.mkdirSync(execDir, { recursive: true })
  const summaryFile = path.join(execDir, filename)
  await generateExecutiveSummary(
    destFile,
    summaryFile,
    executiveSummaryPromptPath,
    llmModel
  )

  // Step 7: Find latest weekly notes
  const latestWeeklyNotes = findLatestWeeklyNotes(targetDir)

  // Step 8: Select meeting notes section
  const executiveSummaryContent = fs.readFileSync(summaryFile, "utf-8")
  const selection = await selectMeetingNotesSection(
    latestWeeklyNotes,
    executiveSummaryContent,
    llmModel
  )

  // Step 9: Generate detailed notes
  const detailedNotes = await generateDetailedNotes(
    destFile,
    detailedNotesPromptPath,
    llmModel
  )

  // Step 10: Update meeting notes file
  const canonical = extractCanonicalName(selection)
  const meetingNotesFile = path.join(targetDir, "Meeting Notes", `${canonical}.md`)
  const wikilinkName = path.basename(filename, ".md")
  const transcriptLink = `[[Transcripts/${meetingDate}/${wikilinkName}|Transcript]]`
  const summaryLink = `[[Executive Summaries/${meetingDate}/${wikilinkName}|Executive Summary]]`

  updateMeetingNotesFile({
    meetingNotesFile,
    meetingDate,
    transcriptLink,
    summaryLink,
    detailedNotes,
  })
}
