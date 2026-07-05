import * as fs from "node:fs/promises"
import * as path from "node:path"

import { extractUid } from "../frontmatter/parse.js"
import {
  formatLocalDateYYYYMMDD,
  resolveBrainRoot,
} from "../notes/createDailyProjectNote.js"
import { formatWikilink, pathToDisplayPath } from "../wikilinks/patterns.js"

export interface BrainFileActionOptions {
  brainRoot?: string
  filePath: string
}

export interface BrainWikilinkResult {
  brainRoot: string
  filePath: string
  relativePath: string
  displayPath: string
  wikilink: string
}

export interface AppendWeeklyNoteTodoOptions {
  brainRoot?: string
  date?: Date
  text: string
  weeklyNotePath?: string
}

export interface AppendWeeklyNoteTodoResult {
  brainRoot: string
  weeklyNotePath: string
  line: string
  updated: boolean
  alreadyPresent: boolean
}

export interface AppendProjectReferenceOptions {
  brainRoot?: string
  referencesPath: string
  heading: string
  reference: string
}

export interface AppendProjectReferenceResult {
  brainRoot: string
  referencesPath: string
  heading: string
  line: string
  updated: boolean
  alreadyPresent: boolean
}

interface ResolvedInsideBrainRoot {
  brainRoot: string
  absolutePath: string
  relativePath: string
}

const DATE_INPUT_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/

function normalizeRelativePath(relativePath: string): string {
  return relativePath.split(path.sep).join("/")
}

function isInsideRelativePath(relativePath: string): boolean {
  return (
    relativePath !== "" &&
    !relativePath.startsWith("..") &&
    !path.isAbsolute(relativePath)
  )
}

async function realpathOrResolved(filePath: string): Promise<string> {
  try {
    return await fs.realpath(filePath)
  } catch {
    return path.resolve(filePath)
  }
}

async function resolveInsideBrainRoot(
  brainRootInput: string | undefined,
  targetPath: string,
  label: string
): Promise<ResolvedInsideBrainRoot> {
  const brainRoot = await resolveBrainRoot(brainRootInput)
  const configuredBrainRoot = path.resolve(brainRoot)
  const configuredTargetPath = path.resolve(targetPath)
  const relativePath = path.relative(configuredBrainRoot, configuredTargetPath)

  if (!isInsideRelativePath(relativePath)) {
    throw new Error(
      `${label} is outside the configured Brain folder: ${brainRoot}`
    )
  }

  let absolutePath = configuredTargetPath

  try {
    const realBrainRoot = await realpathOrResolved(configuredBrainRoot)
    const realTargetPath = await fs.realpath(configuredTargetPath)
    const realRelativePath = path.relative(realBrainRoot, realTargetPath)

    if (!isInsideRelativePath(realRelativePath)) {
      throw new Error(
        `${label} is outside the configured Brain folder: ${brainRoot}`
      )
    }

    absolutePath = realTargetPath
  } catch (error) {
    if (
      error instanceof Error &&
      "code" in error &&
      error.code === "ENOENT"
    ) {
      return {
        brainRoot,
        absolutePath,
        relativePath: normalizeRelativePath(relativePath),
      }
    }

    throw error
  }

  return {
    brainRoot,
    absolutePath,
    relativePath: normalizeRelativePath(relativePath),
  }
}

async function assertMarkdownFile(filePath: string, label: string): Promise<void> {
  const stat = await fs.stat(filePath)

  if (!stat.isFile()) {
    throw new Error(`${label} is not a file: ${filePath}`)
  }

  if (path.extname(filePath) !== ".md") {
    throw new Error(`${label} must be a Markdown file: ${filePath}`)
  }
}

function normalizeSingleLineText(text: string, label: string): string {
  const normalized = text.replace(/\s+/g, " ").trim()

  if (!normalized) {
    throw new Error(`${label} is required`)
  }

  return normalized
}

function startOfWeekSunday(date: Date): Date {
  const weekStart = new Date(date)
  weekStart.setHours(0, 0, 0, 0)
  weekStart.setDate(weekStart.getDate() - weekStart.getDay())
  return weekStart
}

function findSectionBounds(
  lines: string[],
  headingLine: string
): { headingIndex: number; endIndex: number } {
  const headingIndex = lines.findIndex((line) => line.trim() === headingLine)

  if (headingIndex === -1) {
    throw new Error(`Heading "${headingLine.replace(/^## /, "")}" not found`)
  }

  let endIndex = lines.length
  for (let index = headingIndex + 1; index < lines.length; index += 1) {
    const line = lines[index] ?? ""
    if (line.startsWith("## ")) {
      endIndex = index
      break
    }
  }

  return { headingIndex, endIndex }
}

function insertBeforeSectionTrailingBlank(
  lines: string[],
  sectionStartIndex: number,
  sectionEndIndex: number,
  line: string
): void {
  let insertionIndex = sectionEndIndex

  while (
    insertionIndex > sectionStartIndex + 1 &&
    lines[insertionIndex - 1]?.trim() === ""
  ) {
    insertionIndex -= 1
  }

  lines.splice(insertionIndex, 0, line)
}

export function parseLocalDateYYYYMMDD(input: string): Date {
  const trimmed = input.trim()
  const match = trimmed.match(DATE_INPUT_PATTERN)

  if (!match) {
    throw new Error("Date must use YYYY-MM-DD format")
  }

  const year = Number.parseInt(match[1] ?? "", 10)
  const month = Number.parseInt(match[2] ?? "", 10)
  const day = Number.parseInt(match[3] ?? "", 10)
  const date = new Date(year, month - 1, day)

  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    throw new Error("Date must be a valid date")
  }

  return date
}

export async function createPathWikilinkForFile(
  options: BrainFileActionOptions
): Promise<BrainWikilinkResult> {
  const resolved = await resolveInsideBrainRoot(
    options.brainRoot,
    options.filePath,
    "File"
  )
  await assertMarkdownFile(resolved.absolutePath, "File")

  const displayPath = pathToDisplayPath(resolved.relativePath)

  return {
    brainRoot: resolved.brainRoot,
    filePath: resolved.absolutePath,
    relativePath: resolved.relativePath,
    displayPath,
    wikilink: formatWikilink(null, displayPath),
  }
}

export async function createUidWikilinkForFile(
  options: BrainFileActionOptions
): Promise<BrainWikilinkResult> {
  const pathLink = await createPathWikilinkForFile(options)
  const content = await fs.readFile(pathLink.filePath, "utf8")
  const uid = extractUid(content)

  if (!uid) {
    throw new Error(`${pathLink.relativePath} does not have a uid in frontmatter`)
  }

  return {
    ...pathLink,
    wikilink: formatWikilink(uid, pathLink.displayPath),
  }
}

export async function appendWeeklyNoteTodo(
  options: AppendWeeklyNoteTodoOptions
): Promise<AppendWeeklyNoteTodoResult> {
  const brainRoot = await resolveBrainRoot(options.brainRoot)
  const date = options.date ?? new Date()
  const weekStart = startOfWeekSunday(date)
  const defaultWeeklyPath = path.join(
    brainRoot,
    "Weekly Notes",
    `Week of ${formatLocalDateYYYYMMDD(weekStart)}.md`
  )
  const weeklyNotePath = options.weeklyNotePath ?? defaultWeeklyPath
  const resolved = await resolveInsideBrainRoot(
    brainRoot,
    weeklyNotePath,
    "Weekly note"
  )

  if (!resolved.relativePath.startsWith("Weekly Notes/")) {
    throw new Error(
      `Weekly note must be inside Weekly Notes: ${resolved.relativePath}`
    )
  }

  try {
    await assertMarkdownFile(resolved.absolutePath, "Weekly note")
  } catch (error) {
    if (error instanceof Error && error.message.includes("ENOENT")) {
      throw new Error(`Weekly note not found: ${weeklyNotePath}`)
    }

    throw error
  }

  const todoText = normalizeSingleLineText(options.text, "TODO text")
  const line = `- [ ] ${todoText}`
  const content = await fs.readFile(resolved.absolutePath, "utf8")
  const lines = content.split(/\r?\n/)
  const { headingIndex, endIndex } = findSectionBounds(lines, "## TODO")
  const alreadyPresent = lines
    .slice(headingIndex + 1, endIndex)
    .some((candidate) => candidate.trim() === line)

  if (alreadyPresent) {
    return {
      brainRoot,
      weeklyNotePath: resolved.absolutePath,
      line,
      updated: false,
      alreadyPresent: true,
    }
  }

  insertBeforeSectionTrailingBlank(lines, headingIndex, endIndex, line)
  await fs.writeFile(resolved.absolutePath, lines.join("\n"))

  return {
    brainRoot,
    weeklyNotePath: resolved.absolutePath,
    line,
    updated: true,
    alreadyPresent: false,
  }
}

export function extractMarkdownLevelTwoHeadings(content: string): string[] {
  return content
    .split(/\r?\n/)
    .map((line) => line.match(/^##\s+(.+?)\s*$/)?.[1])
    .filter((heading): heading is string => heading !== undefined)
}

export async function appendProjectReference(
  options: AppendProjectReferenceOptions
): Promise<AppendProjectReferenceResult> {
  const resolved = await resolveInsideBrainRoot(
    options.brainRoot,
    options.referencesPath,
    "Project references file"
  )

  if (
    !resolved.relativePath.startsWith("Projects/") ||
    path.basename(resolved.relativePath) !== "references.md"
  ) {
    throw new Error(
      `Project references file must be a Projects/*/references.md file: ${resolved.relativePath}`
    )
  }

  await assertMarkdownFile(resolved.absolutePath, "Project references file")

  const heading = normalizeSingleLineText(options.heading, "Heading")
  const reference = normalizeSingleLineText(options.reference, "Reference")
  const line = reference.startsWith("- ") ? reference : `- ${reference}`
  const content = await fs.readFile(resolved.absolutePath, "utf8")
  const lines = content.split(/\r?\n/)
  const headingLine = `## ${heading}`
  const { headingIndex, endIndex } = findSectionBounds(lines, headingLine)
  const alreadyPresent = lines
    .slice(headingIndex + 1, endIndex)
    .some((candidate) => candidate.trim() === line)

  if (alreadyPresent) {
    return {
      brainRoot: resolved.brainRoot,
      referencesPath: resolved.absolutePath,
      heading,
      line,
      updated: false,
      alreadyPresent: true,
    }
  }

  insertBeforeSectionTrailingBlank(lines, headingIndex, endIndex, line)
  await fs.writeFile(resolved.absolutePath, lines.join("\n"))

  return {
    brainRoot: resolved.brainRoot,
    referencesPath: resolved.absolutePath,
    heading,
    line,
    updated: true,
    alreadyPresent: false,
  }
}
