import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

export type CreateDailyProjectNoteOptions = {
  /** Human title shown in the file header; also used to derive filename. */
  title: string;
  /** Override the Brain root folder. If omitted, uses env + defaults. */
  brainRoot?: string;
  /** Override date (local). Defaults to now. */
  date?: Date;
}

export type CreateDailyProjectNoteResult = {
  brainRoot: string;
  dateFolder: string;
  filePath: string;
  number: number;
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

  const contents = `# ${title}\n\n`
  await fs.writeFile(filePath, contents, { flag: "wx" })

  return { brainRoot, dateFolder, filePath, number }
}
