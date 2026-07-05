import * as fs from "node:fs/promises"
import type { Dirent } from "node:fs"
import * as path from "node:path"

import {
  getFastRecentBrainFiles,
  getGitMarkdownStatuses,
} from "../commands/recentBrainFileCandidates"
import { rankRecentBrainFiles } from "../commands/recentBrainFileRanking"
import { formatDate, getDayName, getWeekDays, getWeekLabel } from "./weekUtils"

export const BRAIN_FILE_CONTEXT_VALUE = "brainFile"
export const SIDEBAR_RECENT_FILE_LIMIT = 10
export const SIDEBAR_EXPANDED_STATE_MAX_DYNAMIC_ITEMS = 128
export const SIDEBAR_EXPANDED_STATE_TTL_MS = 30 * 24 * 60 * 60 * 1000

export type BrainSidebarSection = "today" | "week" | "recent" | "active"
export type SidebarExpandedState = Record<string, SidebarExpandedStateEntry>

export interface SidebarExpandedStateEntry {
  expanded: boolean
  updatedAt: string
}

export interface SidebarFileCandidate {
  absolutePath: string
  description: string
  label: string
  relativePath: string
}

export interface SidebarScheduleItem {
  description: string
  filePath?: string
  time: string
}

export interface WeekDayInfo {
  date: string
  dayName: string
  isToday: boolean
}

interface ErrorWithCode extends Error {
  code?: string
}

const FILE_NUMBER_PREFIX_PATTERN = /^(\d+)/
const SIDEBAR_SECTIONS: BrainSidebarSection[] = [
  "today",
  "week",
  "recent",
  "active",
]

function isErrorWithCode(error: unknown): error is ErrorWithCode {
  return error instanceof Error && "code" in error
}

function normalizePath(filePath: string): string {
  return filePath.replace(/\\/g, "/")
}

function getRelativePath(brainRoot: string, absolutePath: string): string | null {
  const relativePath = path.relative(brainRoot, absolutePath)

  if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
    return null
  }

  return normalizePath(relativePath)
}

async function pathExists(filePath: string): Promise<boolean> {
  try {
    await fs.stat(filePath)
    return true
  } catch (error) {
    if (isErrorWithCode(error) && error.code === "ENOENT") {
      return false
    }

    throw error
  }
}

async function readDirectoryIfExists(
  directoryPath: string
): Promise<Dirent[]> {
  try {
    return await fs.readdir(directoryPath, { withFileTypes: true })
  } catch (error) {
    if (isErrorWithCode(error) && error.code === "ENOENT") {
      return []
    }

    throw error
  }
}

function getFileNumberPrefix(fileName: string): number | null {
  const number = fileName.match(FILE_NUMBER_PREFIX_PATTERN)?.[1]
  return number ? Number.parseInt(number, 10) : null
}

function compareNoteFileNames(left: string, right: string): number {
  const leftNumber = getFileNumberPrefix(left)
  const rightNumber = getFileNumberPrefix(right)

  if (leftNumber !== null && rightNumber !== null && leftNumber !== rightNumber) {
    return rightNumber - leftNumber
  }

  if (leftNumber !== null && rightNumber === null) {
    return -1
  }

  if (leftNumber === null && rightNumber !== null) {
    return 1
  }

  return left.localeCompare(right)
}

function labelFromPath(filePath: string): string {
  return path.basename(filePath, ".md")
}

function createFileCandidate(
  brainRoot: string,
  absolutePath: string,
  description: string
): SidebarFileCandidate | null {
  const relativePath = getRelativePath(brainRoot, absolutePath)
  if (!relativePath?.endsWith(".md")) {
    return null
  }

  return {
    absolutePath,
    description,
    label: labelFromPath(relativePath),
    relativePath,
  }
}

export function getSidebarSectionItemId(
  section: BrainSidebarSection
): string {
  return `section:${section}`
}

export function getSidebarDayItemId(date: string): string {
  return `day:${date}`
}

function getSidebarSectionItemIds(): Set<string> {
  return new Set(SIDEBAR_SECTIONS.map(getSidebarSectionItemId))
}

function toExpandedStateEntry(
  value: unknown,
  now: Date
): SidebarExpandedStateEntry | null {
  if (typeof value === "boolean") {
    return {
      expanded: value,
      updatedAt: now.toISOString(),
    }
  }

  if (typeof value !== "object" || value === null) {
    return null
  }

  const maybeEntry = value as Partial<SidebarExpandedStateEntry>
  if (typeof maybeEntry.expanded !== "boolean") {
    return null
  }

  const updatedAt =
    typeof maybeEntry.updatedAt === "string" &&
    !Number.isNaN(Date.parse(maybeEntry.updatedAt))
      ? maybeEntry.updatedAt
      : now.toISOString()

  return {
    expanded: maybeEntry.expanded,
    updatedAt,
  }
}

export function pruneSidebarExpandedState(
  rawState: Record<string, unknown>,
  now = new Date()
): SidebarExpandedState {
  const sectionIds = getSidebarSectionItemIds()
  const cutoff = now.getTime() - SIDEBAR_EXPANDED_STATE_TTL_MS
  const sectionEntries: SidebarExpandedState = {}
  const dynamicEntries: Array<[string, SidebarExpandedStateEntry]> = []

  for (const [itemId, rawValue] of Object.entries(rawState)) {
    const entry = toExpandedStateEntry(rawValue, now)
    if (!entry) {
      continue
    }

    if (sectionIds.has(itemId)) {
      sectionEntries[itemId] = entry
      continue
    }

    if (Date.parse(entry.updatedAt) < cutoff) {
      continue
    }

    dynamicEntries.push([itemId, entry])
  }

  dynamicEntries.sort(
    ([leftId, left], [rightId, right]) =>
      Date.parse(right.updatedAt) - Date.parse(left.updatedAt) ||
      leftId.localeCompare(rightId)
  )

  return Object.fromEntries([
    ...Object.entries(sectionEntries),
    ...dynamicEntries.slice(0, SIDEBAR_EXPANDED_STATE_MAX_DYNAMIC_ITEMS),
  ])
}

export function setSidebarExpandedStateItem(
  rawState: Record<string, unknown>,
  itemId: string,
  expanded: boolean,
  now = new Date()
): SidebarExpandedState {
  return pruneSidebarExpandedState(
    {
      ...rawState,
      [itemId]: {
        expanded,
        updatedAt: now.toISOString(),
      },
    },
    now
  )
}

export function getWeekDayInfos(weekStart: Date, today = new Date()): WeekDayInfo[] {
  const todayStr = formatDate(today)

  return getWeekDays(weekStart).map((day) => {
    const date = formatDate(day)
    return {
      date,
      dayName: getDayName(day),
      isToday: date === todayStr,
    }
  })
}

export async function getWeeklyNoteFile(
  brainRoot: string,
  weekStart: Date
): Promise<SidebarFileCandidate | null> {
  const weekLabel = getWeekLabel(weekStart)
  const weeklyNotePath = path.join(brainRoot, "Weekly Notes", `${weekLabel}.md`)

  if (!(await pathExists(weeklyNotePath))) {
    return null
  }

  return createFileCandidate(brainRoot, weeklyNotePath, "Weekly Note")
}

export async function getDailyProjectFiles(
  brainRoot: string,
  date: string
): Promise<SidebarFileCandidate[]> {
  const dayFolder = path.join(brainRoot, "Daily Projects", date)
  const entries = await readDirectoryIfExists(dayFolder)

  return entries
    .filter(
      (entry) =>
        entry.isFile() && entry.name.endsWith(".md") && !entry.name.startsWith(".")
    )
    .sort((left, right) => compareNoteFileNames(left.name, right.name))
    .map((entry) =>
      createFileCandidate(brainRoot, path.join(dayFolder, entry.name), date)
    )
    .filter((file): file is SidebarFileCandidate => file !== null)
}

function meetingNoteFileName(noteName: string): string {
  return noteName.toLowerCase().endsWith(".md") ? noteName : `${noteName}.md`
}

export async function getWeeklyScheduleItems(
  brainRoot: string,
  weekStart: Date,
  date: string
): Promise<SidebarScheduleItem[]> {
  const weeklyNote = await getWeeklyNoteFile(brainRoot, weekStart)
  if (!weeklyNote) {
    return []
  }

  const content = await fs.readFile(weeklyNote.absolutePath, "utf-8")
  const scheduleMatch = content.match(/^## Schedule\s*$/m)
  if (!scheduleMatch || scheduleMatch.index === undefined) {
    return []
  }

  const scheduleStart = scheduleMatch.index + scheduleMatch[0].length
  const nextSectionMatch = content.slice(scheduleStart).match(/^## /m)
  const scheduleContent = nextSectionMatch
    ? content.slice(scheduleStart, scheduleStart + nextSectionMatch.index!)
    : content.slice(scheduleStart)
  const meetingWikilinkPattern =
    /^\[\[Meeting Notes\/([^/]+)\/\d{4}-\d{2}-\d{2}\/([^\]|]+)(?:\|[^\]]+)?\]\]$/
  const scheduleItems: SidebarScheduleItem[] = []
  let currentDate: string | null = null

  for (const line of scheduleContent.split("\n")) {
    const dayMatch = line.match(/^- \w+ \((\d{4}-\d{2}-\d{2})\)/)
    if (dayMatch) {
      currentDate = dayMatch[1]!
      continue
    }

    if (currentDate !== date) {
      continue
    }

    const itemMatch = line.match(/^\s*-\s*\[[ xX]\]\s*(\d{4})\s*(.+)$/)
    if (!itemMatch) {
      continue
    }

    const time = itemMatch[1]!
    const descriptionPart = itemMatch[2]!.trim()
    const wikilinkMatch = descriptionPart.match(meetingWikilinkPattern)

    if (wikilinkMatch) {
      const meetingTarget = wikilinkMatch[1]!
      const noteName = wikilinkMatch[2]!
      scheduleItems.push({
        time,
        description: meetingTarget,
        filePath: path.join(
          brainRoot,
          "Meeting Notes",
          meetingTarget,
          date,
          meetingNoteFileName(noteName)
        ),
      })
      continue
    }

    scheduleItems.push({ time, description: descriptionPart })
  }

  return scheduleItems.sort((left, right) => left.time.localeCompare(right.time))
}

export function getActiveContextFile(
  brainRoot: string,
  activeFilePath: string | undefined
): SidebarFileCandidate | null {
  if (!activeFilePath?.endsWith(".md")) {
    return null
  }

  const relativePath = getRelativePath(brainRoot, activeFilePath)
  if (!relativePath) {
    return null
  }

  return createFileCandidate(
    brainRoot,
    activeFilePath,
    normalizePath(path.dirname(relativePath)) === "."
      ? "Brain root"
      : normalizePath(path.dirname(relativePath))
  )
}

export async function getRecentSidebarFiles(
  brainRoot: string,
  options: { limit?: number; now?: Date } = {}
): Promise<SidebarFileCandidate[]> {
  const limit = options.limit ?? SIDEBAR_RECENT_FILE_LIMIT
  let gitStatuses = new Map<string, string>()

  try {
    gitStatuses = await getGitMarkdownStatuses(brainRoot)
  } catch {
    gitStatuses = new Map()
  }

  const recentFileOptions = options.now
    ? { limit, now: options.now }
    : { limit }
  const rankedFiles = rankRecentBrainFiles(
    await getFastRecentBrainFiles(brainRoot, recentFileOptions),
    gitStatuses,
    limit
  )

  return rankedFiles.map((file) => ({
    absolutePath: file.absolutePath,
    description: file.gitStatus ? `git ${file.gitStatus}` : "recent",
    label: labelFromPath(file.relativePath),
    relativePath: file.relativePath,
  }))
}
