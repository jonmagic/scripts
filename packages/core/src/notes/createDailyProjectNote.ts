import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

import { generateTid } from "../frontmatter/tid.js"
import { serializeFrontmatter } from "../frontmatter/serialize.js"
import { detectSession } from "../session/detectSession.js"

export type CreateDailyProjectNoteOptions = {
  /** Human title shown in the file header; also used to derive filename. */
  title: string;
  /** Override the Brain root folder. If omitted, uses env + defaults. */
  brainRoot?: string;
  /** Override date (local). Defaults to now. */
  date?: Date;
  /** When true, add a link to this note in the current weekly note. */
  updateWeeklyNote?: boolean;
  /** Override weekly note path. If omitted, it is derived from date + brainRoot. */
  weeklyNotePath?: string;
  /**
   * Override the session resume command to embed in frontmatter.
   * If omitted, auto-detection is attempted. Pass `false` to disable.
   */
  session?: string | false;
}

export type CreateDailyProjectNoteResult = {
  brainRoot: string;
  dateFolder: string;
  filePath: string;
  number: number;
  uid: string;
  session?: string;
  weeklyNotePath?: string;
  weeklyNoteUpdated?: boolean;
}

function pad2(n: number): string {
  return n.toString().padStart(2, "0")
}

export function formatLocalDateYYYYMMDD(date: Date): string {
  const yyyy = date.getFullYear()
  const mm = pad2(date.getMonth() + 1)
  const dd = pad2(date.getDate())
  return `${yyyy}-${mm}-${dd}`
}

export async function resolveBrainRoot(explicit?: string): Promise<string> {
  const envRoot = process.env.BRAIN_ROOT?.trim()
  const home = os.homedir()

  const candidates = [
    explicit?.trim(),
    envRoot,
    "/Users/jonmagic/Brain",
    path.join(home, "Brain")
  ].filter((p): p is string => Boolean(p))

  for (const candidate of candidates) {
    try {
      const st = await fs.stat(candidate)
      if (st.isDirectory()) {
        return candidate
      }
    } catch {
      // ignore
    }
  }

  throw new Error(
    [
      "Brain root folder not found.",
      "Looked in:",
      ...candidates.map((c) => `- ${c}`),
      "Create the folder or set BRAIN_ROOT to the correct path."
    ].join("\n")
  )
}

const DAY_NAMES = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday"
]

function startOfWeekSunday(date: Date): Date {
  const d = new Date(date)
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() - d.getDay())
  return d
}

function formatRelativePath(filePath: string, root: string): string {
  const rel = path.relative(root, filePath)
  return rel.split(path.sep).join("/")
}

async function updateWeeklyNoteLink(options: {
  brainRoot: string;
  date: Date;
  filePath: string;
  weeklyNotePath?: string;
}): Promise<{ path: string; updated: boolean }> {
  const weekStart = startOfWeekSunday(options.date)
  const weeklyPath =
    options.weeklyNotePath ??
    path.join(
      options.brainRoot,
      "Weekly Notes",
      `Week of ${formatLocalDateYYYYMMDD(weekStart)}.md`
    )

  try {
    await fs.stat(weeklyPath)
  } catch {
    return { path: weeklyPath, updated: false }
  }

  const dayName = DAY_NAMES[options.date.getDay()]
  const heading = `## ${dayName}`
  const relativePath = formatRelativePath(options.filePath, options.brainRoot)
  const link = `- [[${relativePath}]]`

  const raw = await fs.readFile(weeklyPath, "utf8")
  const lines = raw.split(/\r?\n/)

  const headingIndex = lines.findIndex((line) => line.trim() === heading)
  if (headingIndex === -1) {
    const randomNotesIndex = lines.findIndex(
      (line) => line.trim() === "## Random notes"
    )
    const insertIndex = randomNotesIndex === -1 ? lines.length : randomNotesIndex
    lines.splice(insertIndex, 0, heading, link, "")
  } else {
    let sectionEndIndex = lines.length
    for (let i = headingIndex + 1; i < lines.length; i += 1) {
      const line = lines[i] ?? ""
      if (line.startsWith("## ")) {
        sectionEndIndex = i
        break
      }
    }

    const alreadyPresent = lines
      .slice(headingIndex + 1, sectionEndIndex)
      .some((line) => line.trim() === link)

    if (!alreadyPresent) {
      let insertionPoint = headingIndex + 1
      if (lines[insertionPoint]?.trim() === "") {
        insertionPoint += 1
      }
      lines.splice(insertionPoint, 0, link)
    }
  }

  await fs.writeFile(weeklyPath, lines.join("\n"))
  return { path: weeklyPath, updated: true }
}

export function sanitizeTitleForFilename(title: string): string {
  // Keep it readable, but safe-ish across filesystems.
  return title
    .trim()
    .toLowerCase()
    .replace(/[\\/]+/g, "-")
    .replace(/[:*?"<>|]+/g, "")
    .replace(/\s+/g, " ")
}

async function nextDailyNumber(dir: string): Promise<number> {
  let entries: string[] = []
  try {
    entries = await fs.readdir(dir)
  } catch {
    return 1
  }

  let max = 0
  for (const name of entries) {
    const m = name.match(/^(\d{2})\b/)
    if (!m) {
      continue
    }
    const n = Number(m[1])
    if (Number.isFinite(n)) {
      max = Math.max(max, n)
    }
  }

  return max + 1
}

/**
 * Creates a new numbered markdown file in:
 *   `Daily Projects/YYYY-MM-DD/NN {title}.md`
 */
export async function createDailyProjectNote(
  options: CreateDailyProjectNoteOptions
): Promise<CreateDailyProjectNoteResult> {
  const title = options.title.trim()
  if (!title) throw new Error("Title is required")

  const brainRoot = await resolveBrainRoot(options.brainRoot)
  const date = options.date ?? new Date()
  const ymd = formatLocalDateYYYYMMDD(date)

  const dateFolder = path.join(brainRoot, "Daily Projects", ymd)
  await fs.mkdir(dateFolder, { recursive: true })

  const number = await nextDailyNumber(dateFolder)
  const fileName = `${pad2(number)} ${sanitizeTitleForFilename(title)}.md`
  const filePath = path.join(dateFolder, fileName)

  // Generate frontmatter
  const uid = generateTid()
  const created = `${ymd}T00:00:00Z`

  // Resolve session: use explicit value, auto-detect, or skip
  let sessionResume: string | undefined
  if (options.session === false) {
    // Explicitly disabled
  } else if (typeof options.session === "string") {
    sessionResume = options.session
  } else {
    // Auto-detect from environment
    try {
      const detected = detectSession(brainRoot)
      if (detected) {
        sessionResume = detected.resume
      }
    } catch {
      // Session detection is best-effort; don't fail note creation
    }
  }

  const frontmatter = serializeFrontmatter({
    uid,
    type: "daily.project",
    created,
    tags: [],
    ...(sessionResume ? { session: sessionResume } : {}),
  })

  const contents = `${frontmatter}\n\n# ${title}\n\n`
  await fs.writeFile(filePath, contents, { flag: "wx" })

  let weeklyNotePath: string | undefined
  let weeklyNoteUpdated: boolean | undefined
  if (options.updateWeeklyNote !== false) {
    const updateOptions = {
      brainRoot,
      date,
      filePath,
      ...(options.weeklyNotePath ? { weeklyNotePath: options.weeklyNotePath } : {})
    }
    const result = await updateWeeklyNoteLink(updateOptions)
    weeklyNotePath = result.path
    weeklyNoteUpdated = result.updated
  }

  const result: CreateDailyProjectNoteResult = {
    brainRoot,
    dateFolder,
    filePath,
    number,
    uid,
  }

  if (sessionResume) {
    result.session = sessionResume
  }

  if (weeklyNotePath) {
    result.weeklyNotePath = weeklyNotePath
  }
  if (weeklyNoteUpdated !== undefined) {
    result.weeklyNoteUpdated = weeklyNoteUpdated
  }

  return result
}
