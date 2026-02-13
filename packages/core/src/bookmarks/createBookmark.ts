import * as fs from "node:fs/promises"
import * as path from "node:path"

import { generateTid } from "../frontmatter/tid.js"
import { serializeFrontmatter } from "../frontmatter/serialize.js"
import { resolveBrainRoot, formatLocalDateYYYYMMDD } from "../notes/createDailyProjectNote.js"

export type CreateBookmarkOptions = {
  /** The URL to bookmark. */
  url: string
  /** Page title. If omitted, must be fetched externally or derived from URL. */
  title?: string
  /** User's blurb or AI summary to use as the file body. */
  blurb?: string
  /** Where the bookmark was found (e.g. "hacker-news", "slack"). */
  source?: string
  /** Tags for the bookmark. */
  tags?: string[]
  /** Override the Brain root folder. If omitted, uses env + defaults. */
  brainRoot?: string
  /** Override date (local). Defaults to now. */
  date?: Date
}

export type CreateBookmarkResult = {
  brainRoot: string
  dateFolder: string
  filePath: string
  number: number
  uid: string
  url: string
  title: string
}

function pad2(n: number): string {
  return n.toString().padStart(2, "0")
}

/**
 * Derive a filename-safe slug from a page title.
 * Keeps it readable: lowercase, spaces to hyphens, strip unsafe chars.
 */
export function slugifyTitle(title: string): string {
  return title
    .trim()
    .toLowerCase()
    .replace(/[\\/]+/g, "-")
    .replace(/[:*?"<>|]+/g, "")
    .replace(/\s+/g, " ")
}

/**
 * Find the next sequential number in a date folder.
 */
async function nextBookmarkNumber(dir: string): Promise<number> {
  let entries: string[] = []
  try {
    entries = await fs.readdir(dir)
  } catch {
    return 1
  }

  let max = 0
  for (const name of entries) {
    const m = name.match(/^(\d{2})\b/)
    if (!m) continue
    const n = Number(m[1])
    if (Number.isFinite(n)) {
      max = Math.max(max, n)
    }
  }

  return max + 1
}

/**
 * Derive a title from a URL when no title is provided.
 * Uses the last meaningful path segment or hostname.
 */
export function titleFromUrl(url: string): string {
  try {
    const parsed = new URL(url)
    const segments = parsed.pathname
      .split("/")
      .filter((s) => s.length > 0)

    if (segments.length > 0) {
      const last = segments[segments.length - 1]!
      return last
        .replace(/[-_]+/g, " ")
        .replace(/\.\w+$/, "") // strip file extension
        .trim()
    }

    return parsed.hostname.replace(/^www\./, "")
  } catch {
    return "untitled bookmark"
  }
}

/**
 * Creates a new bookmark file in:
 *   `Bookmarks/YYYY-MM-DD/NN title.md`
 */
export async function createBookmark(
  options: CreateBookmarkOptions
): Promise<CreateBookmarkResult> {
  const url = options.url.trim()
  if (!url) throw new Error("URL is required")

  const brainRoot = await resolveBrainRoot(options.brainRoot)
  const date = options.date ?? new Date()
  const ymd = formatLocalDateYYYYMMDD(date)

  const dateFolder = path.join(brainRoot, "Bookmarks", ymd)
  await fs.mkdir(dateFolder, { recursive: true })

  const title = options.title?.trim() || titleFromUrl(url)
  const number = await nextBookmarkNumber(dateFolder)
  const fileName = `${pad2(number)} ${slugifyTitle(title)}.md`
  const filePath = path.join(dateFolder, fileName)

  const uid = generateTid()
  const created = `${ymd}T00:00:00Z`

  const frontmatter = serializeFrontmatter({
    uid,
    type: "bookmark",
    created,
    url,
    title,
    ...(options.source ? { source: options.source } : {}),
    ...(options.tags && options.tags.length > 0 ? { tags: options.tags } : {}),
  })

  const body = options.blurb?.trim() || ""
  const contents = body
    ? `${frontmatter}\n\n${body}\n`
    : `${frontmatter}\n`

  await fs.writeFile(filePath, contents, { flag: "wx" })

  return {
    brainRoot,
    dateFolder,
    filePath,
    number,
    uid,
    url,
    title,
  }
}
