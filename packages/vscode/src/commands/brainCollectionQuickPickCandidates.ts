import type { Dirent } from "node:fs"
import * as fs from "node:fs/promises"
import * as path from "node:path"

export type BrainCollection =
  | "dailyProjects"
  | "weeklyNotes"
  | "projectNotes"
  | "meetingNotes"
  | "bookmarks"

export interface BrainCollectionCandidate {
  absolutePath: string
  relativePath: string
  label: string
  description: string
  detail: string
}

export interface BrainCollectionCandidateResult {
  candidates: BrainCollectionCandidate[]
  emptyMessage: string
  placeHolder: string
  title: string
}

export interface BrainCollectionCandidateOptions {
  limit?: number
  maxDateFolders?: number
  maxFilesPerFolder?: number
  maxProjectDepth?: number
  maxProjectDirectories?: number
  maxProjectFiles?: number
  maxTopLevelFolders?: number
}

interface BrainCollectionConfig {
  collectionPath: string
  emptySearchDescription: string
  placeHolder: string
  title: string
}

interface DateFolder {
  absolutePath: string
  date: string
  name: string
}

interface MeetingDateFolder extends DateFolder {
  meetingTarget: string
}

interface ProjectFile {
  absolutePath: string
  depth: number
  relativePath: string
}

interface ProjectDirectoryQueueItem {
  depth: number
  directoryPath: string
}

interface RequiredBrainCollectionCandidateOptions {
  limit: number
  maxDateFolders: number
  maxFilesPerFolder: number
  maxProjectDepth: number
  maxProjectDirectories: number
  maxProjectFiles: number
  maxTopLevelFolders: number
}

interface ErrorWithCode extends Error {
  code?: string
}

const DATE_PREFIX_PATTERN = /^(\d{4}-\d{2}-\d{2})(?:$|-.*)/
const WEEKLY_NOTE_PATTERN = /^Week of (\d{4}-\d{2}-\d{2})\.md$/

const DEFAULT_OPTIONS: RequiredBrainCollectionCandidateOptions = {
  limit: 50,
  maxDateFolders: 50,
  maxFilesPerFolder: 20,
  maxProjectDepth: 2,
  maxProjectDirectories: 200,
  maxProjectFiles: 200,
  maxTopLevelFolders: 200,
}

const PROJECT_DEFAULT_OPTIONS: RequiredBrainCollectionCandidateOptions = {
  ...DEFAULT_OPTIONS,
  limit: 500,
  maxProjectDirectories: 500,
  maxProjectFiles: 500,
}

const COLLECTION_CONFIGS: Record<BrainCollection, BrainCollectionConfig> = {
  dailyProjects: {
    collectionPath: "Daily Projects",
    emptySearchDescription: "searched recent date-prefixed Daily Projects folders",
    placeHolder: "Choose a Daily Project note",
    title: "Open Daily Project",
  },
  weeklyNotes: {
    collectionPath: "Weekly Notes",
    emptySearchDescription: "searched Week of YYYY-MM-DD Markdown files",
    placeHolder: "Choose a Weekly Note",
    title: "Open Weekly Note",
  },
  projectNotes: {
    collectionPath: "Projects",
    emptySearchDescription:
      "searched Markdown files under Projects up to two directory levels deep",
    placeHolder: "Choose a Project note",
    title: "Open Project Note",
  },
  meetingNotes: {
    collectionPath: "Meeting Notes",
    emptySearchDescription:
      "searched recent date-prefixed Meeting Notes folders",
    placeHolder: "Choose a Meeting Note",
    title: "Open Meeting Note",
  },
  bookmarks: {
    collectionPath: "Bookmarks",
    emptySearchDescription: "searched recent date-prefixed Bookmarks folders",
    placeHolder: "Choose a Bookmark",
    title: "Open Bookmark",
  },
}

function normalizePath(filePath: string): string {
  return filePath.replace(/\\/g, "/")
}

function normalizeCount(value: number | undefined, fallback: number): number {
  if (value === undefined) {
    return fallback
  }

  return Math.max(0, Math.floor(value))
}

function normalizeOptions(
  collection: BrainCollection,
  options: BrainCollectionCandidateOptions = {}
): RequiredBrainCollectionCandidateOptions {
  const defaults =
    collection === "projectNotes" ? PROJECT_DEFAULT_OPTIONS : DEFAULT_OPTIONS

  return {
    limit: normalizeCount(options.limit, defaults.limit),
    maxDateFolders: normalizeCount(
      options.maxDateFolders,
      defaults.maxDateFolders
    ),
    maxFilesPerFolder: normalizeCount(
      options.maxFilesPerFolder,
      defaults.maxFilesPerFolder
    ),
    maxProjectDepth: normalizeCount(
      options.maxProjectDepth,
      defaults.maxProjectDepth
    ),
    maxProjectDirectories: normalizeCount(
      options.maxProjectDirectories,
      defaults.maxProjectDirectories
    ),
    maxProjectFiles: normalizeCount(
      options.maxProjectFiles,
      defaults.maxProjectFiles
    ),
    maxTopLevelFolders: normalizeCount(
      options.maxTopLevelFolders,
      defaults.maxTopLevelFolders
    ),
  }
}

function isErrorWithCode(error: unknown): error is ErrorWithCode {
  return error instanceof Error && "code" in error
}

function isValidDate(date: string): boolean {
  const parsed = new Date(`${date}T00:00:00.000Z`)
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === date
}

export function parseDatePrefix(name: string): string | null {
  const match = name.match(DATE_PREFIX_PATTERN)
  const date = match?.[1]
  if (!date) {
    return null
  }

  return isValidDate(date) ? date : null
}

function parseWeeklyNoteDate(name: string): string | null {
  const match = name.match(WEEKLY_NOTE_PATTERN)
  const date = match?.[1]
  if (!date) {
    return null
  }

  return isValidDate(date) ? date : null
}

async function readDirectoryIfExists(directoryPath: string): Promise<Dirent[]> {
  try {
    return (await fs.readdir(directoryPath, { withFileTypes: true })).sort(
      (left, right) => left.name.localeCompare(right.name)
    )
  } catch (error) {
    if (isErrorWithCode(error) && error.code === "ENOENT") {
      return []
    }

    throw error
  }
}

function isVisibleMarkdownFile(entry: Dirent): boolean {
  return entry.isFile() && entry.name.endsWith(".md") && !entry.name.startsWith(".")
}

function isVisibleDirectory(entry: Dirent): boolean {
  return entry.isDirectory() && !entry.name.startsWith(".")
}

function getRelativePath(brainRoot: string, absolutePath: string): string {
  return normalizePath(path.relative(brainRoot, absolutePath))
}

function labelFromRelativePath(relativePath: string): string {
  return path.basename(relativePath, ".md")
}

function createCandidate(
  brainRoot: string,
  absolutePath: string,
  description: string
): BrainCollectionCandidate {
  const relativePath = getRelativePath(brainRoot, absolutePath)

  return {
    absolutePath,
    relativePath,
    label: labelFromRelativePath(relativePath),
    description,
    detail: relativePath,
  }
}

async function listVisibleDirectories(directoryPath: string): Promise<Dirent[]> {
  return (await readDirectoryIfExists(directoryPath)).filter(isVisibleDirectory)
}

async function listMarkdownFiles(directoryPath: string): Promise<Dirent[]> {
  return (await readDirectoryIfExists(directoryPath)).filter(isVisibleMarkdownFile)
}

async function listDateFolders(
  collectionRoot: string,
  limit: number
): Promise<DateFolder[]> {
  return (await listVisibleDirectories(collectionRoot))
    .map((entry) => {
      const date = parseDatePrefix(entry.name)
      if (!date) {
        return null
      }

      return {
        absolutePath: path.join(collectionRoot, entry.name),
        date,
        name: entry.name,
      }
    })
    .filter((folder): folder is DateFolder => folder !== null)
    .sort(
      (left, right) =>
        right.date.localeCompare(left.date) || left.name.localeCompare(right.name)
    )
    .slice(0, limit)
}

async function candidatesFromDateFolders(
  brainRoot: string,
  folders: DateFolder[],
  descriptionForFolder: (folder: DateFolder) => string,
  options: RequiredBrainCollectionCandidateOptions
): Promise<BrainCollectionCandidate[]> {
  const groups = await Promise.all(
    folders.map(async (folder) => {
      const files = (await listMarkdownFiles(folder.absolutePath)).slice(
        0,
        options.maxFilesPerFolder
      )

      return files.map((file) =>
        createCandidate(
          brainRoot,
          path.join(folder.absolutePath, file.name),
          descriptionForFolder(folder)
        )
      )
    })
  )

  return groups.flat().slice(0, options.limit)
}

async function getDateCollectionCandidates(
  brainRoot: string,
  collection: "dailyProjects" | "bookmarks",
  options: RequiredBrainCollectionCandidateOptions
): Promise<BrainCollectionCandidate[]> {
  const collectionRoot = path.join(
    brainRoot,
    COLLECTION_CONFIGS[collection].collectionPath
  )
  const folders = await listDateFolders(collectionRoot, options.maxDateFolders)

  return candidatesFromDateFolders(
    brainRoot,
    folders,
    (folder) => folder.name,
    options
  )
}

async function getWeeklyNoteCandidates(
  brainRoot: string,
  options: RequiredBrainCollectionCandidateOptions
): Promise<BrainCollectionCandidate[]> {
  const collectionRoot = path.join(brainRoot, "Weekly Notes")
  const files = (await listMarkdownFiles(collectionRoot))
    .map((entry) => {
      const date = parseWeeklyNoteDate(entry.name)
      if (!date) {
        return null
      }

      return {
        absolutePath: path.join(collectionRoot, entry.name),
        date,
        name: entry.name,
      }
    })
    .filter((file): file is DateFolder => file !== null)
    .sort(
      (left, right) =>
        right.date.localeCompare(left.date) || left.name.localeCompare(right.name)
    )
    .slice(0, options.limit)

  return files.map((file) =>
    createCandidate(brainRoot, file.absolutePath, "Weekly Notes")
  )
}

async function getMeetingNoteDateFolders(
  brainRoot: string,
  options: RequiredBrainCollectionCandidateOptions
): Promise<MeetingDateFolder[]> {
  const collectionRoot = path.join(brainRoot, "Meeting Notes")
  const meetingTargets = (await listVisibleDirectories(collectionRoot)).slice(
    0,
    options.maxTopLevelFolders
  )
  const groups = await Promise.all(
    meetingTargets.map(async (target) => {
      const targetRoot = path.join(collectionRoot, target.name)
      return (await listVisibleDirectories(targetRoot))
        .map((entry) => {
          const date = parseDatePrefix(entry.name)
          if (!date) {
            return null
          }

          return {
            absolutePath: path.join(targetRoot, entry.name),
            date,
            meetingTarget: target.name,
            name: entry.name,
          }
        })
        .filter((folder): folder is MeetingDateFolder => folder !== null)
    })
  )

  return groups
    .flat()
    .sort(
      (left, right) =>
        right.date.localeCompare(left.date) ||
        left.meetingTarget.localeCompare(right.meetingTarget) ||
        left.name.localeCompare(right.name)
    )
    .slice(0, options.maxDateFolders)
}

async function getMeetingNoteCandidates(
  brainRoot: string,
  options: RequiredBrainCollectionCandidateOptions
): Promise<BrainCollectionCandidate[]> {
  const folders = await getMeetingNoteDateFolders(brainRoot, options)

  return candidatesFromDateFolders(
    brainRoot,
    folders,
    (folder) => {
      const meetingFolder = folder as MeetingDateFolder
      return `${meetingFolder.meetingTarget} · ${meetingFolder.name}`
    },
    options
  )
}

async function collectProjectMarkdownFiles(
  brainRoot: string,
  collectionRoot: string,
  options: RequiredBrainCollectionCandidateOptions
): Promise<ProjectFile[]> {
  const queue: ProjectDirectoryQueueItem[] = [
    { depth: 0, directoryPath: collectionRoot },
  ]
  const files: ProjectFile[] = []
  let directoryCount = 0

  for (let index = 0; index < queue.length; index += 1) {
    if (
      files.length >= options.maxProjectFiles ||
      directoryCount >= options.maxProjectDirectories
    ) {
      break
    }

    const current = queue[index]
    if (!current) {
      break
    }

    const entries = await readDirectoryIfExists(current.directoryPath)

    for (const entry of entries) {
      if (entry.name.startsWith(".")) {
        continue
      }

      const entryPath = path.join(current.directoryPath, entry.name)

      if (entry.isFile() && entry.name.endsWith(".md")) {
        const relativePath = getRelativePath(brainRoot, entryPath)
        files.push({
          absolutePath: entryPath,
          depth: relativePath.split("/").length,
          relativePath,
        })

        if (files.length >= options.maxProjectFiles) {
          break
        }

        continue
      }

      if (entry.isDirectory() && current.depth < options.maxProjectDepth) {
        directoryCount += 1
        if (directoryCount > options.maxProjectDirectories) {
          break
        }

        queue.push({ depth: current.depth + 1, directoryPath: entryPath })
      }
    }
  }

  return files
}

async function getProjectNoteCandidates(
  brainRoot: string,
  options: RequiredBrainCollectionCandidateOptions
): Promise<BrainCollectionCandidate[]> {
  const collectionRoot = path.join(brainRoot, "Projects")
  const files = await collectProjectMarkdownFiles(
    brainRoot,
    collectionRoot,
    options
  )

  return files
    .sort(
      (left, right) =>
        left.depth - right.depth ||
        left.relativePath.localeCompare(right.relativePath)
    )
    .slice(0, options.limit)
    .map((file) =>
      createCandidate(
        brainRoot,
        file.absolutePath,
        normalizePath(path.dirname(file.relativePath))
      )
    )
}

export function getBrainCollectionEmptyMessage(
  brainRoot: string,
  collection: BrainCollection
): string {
  const config = COLLECTION_CONFIGS[collection]
  return `No ${config.title.replace("Open ", "")} Markdown files found in ${path.join(
    brainRoot,
    config.collectionPath
  )}; ${config.emptySearchDescription}.`
}

export async function getBrainCollectionCandidates(
  brainRoot: string,
  collection: BrainCollection,
  rawOptions: BrainCollectionCandidateOptions = {}
): Promise<BrainCollectionCandidateResult> {
  const options = normalizeOptions(collection, rawOptions)
  const config = COLLECTION_CONFIGS[collection]
  let candidates: BrainCollectionCandidate[]

  switch (collection) {
    case "dailyProjects":
    case "bookmarks":
      candidates = await getDateCollectionCandidates(brainRoot, collection, options)
      break
    case "weeklyNotes":
      candidates = await getWeeklyNoteCandidates(brainRoot, options)
      break
    case "projectNotes":
      candidates = await getProjectNoteCandidates(brainRoot, options)
      break
    case "meetingNotes":
      candidates = await getMeetingNoteCandidates(brainRoot, options)
      break
  }

  return {
    candidates,
    emptyMessage: getBrainCollectionEmptyMessage(brainRoot, collection),
    placeHolder: config.placeHolder,
    title: config.title,
  }
}
