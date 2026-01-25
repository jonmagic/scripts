// Wikilink pattern utilities for Brain markdown files.

/**
 * Regex to match wikilinks: [[target]] or [[target|label]]
 * Captures:
 * - Group 1: Full content inside brackets (target or target|label)
 * - Group 2: Target (path or uid:xxx)
 * - Group 3: Label (if present, without the |)
 */
export const WIKILINK_REGEX = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g

/**
 * Prefix for UID-based links
 */
export const UID_PREFIX = "uid:"

/**
 * Parsed wikilink structure
 */
export interface ParsedWikilink {
  /** The full match including brackets */
  full: string
  /** The target: either a path or uid:xxx */
  target: string
  /** Optional display label */
  label?: string
  /** Whether this is a UID-based link */
  isUid: boolean
  /** The UID value (if isUid is true) */
  uid?: string
}

/**
 * Parse a wikilink match into its components.
 * @param match The full [[...]] string or just the inner content
 */
export function parseWikilink(match: string): ParsedWikilink {
  // Strip brackets if present
  let inner = match
  if (inner.startsWith("[[") && inner.endsWith("]]")) {
    inner = inner.slice(2, -2)
  }

  const pipeIndex = inner.indexOf("|")
  let target: string
  let label: string | undefined

  if (pipeIndex !== -1) {
    target = inner.slice(0, pipeIndex)
    label = inner.slice(pipeIndex + 1)
  } else {
    target = inner
    label = undefined
  }

  const isUid = target.startsWith(UID_PREFIX)
  const uid = isUid ? target.slice(UID_PREFIX.length) : undefined

  const result: ParsedWikilink = {
    full: match.startsWith("[[") ? match : `[[${match}]]`,
    target,
    isUid,
  }

  if (label !== undefined) {
    result.label = label
  }
  if (uid !== undefined) {
    result.uid = uid
  }

  return result
}

/**
 * Format a wikilink string.
 * @param uid The UID (if available, will be prefixed with uid:)
 * @param displayPath The display path (used as label for UID links, or as target for path links)
 */
export function formatWikilink(uid: string | null, displayPath: string): string {
  if (uid) {
    return `[[${UID_PREFIX}${uid}|${displayPath}]]`
  }
  return `[[${displayPath}]]`
}

/**
 * Extract all wikilinks from content.
 */
export function extractWikilinks(content: string): ParsedWikilink[] {
  const links: ParsedWikilink[] = []
  const regex = new RegExp(WIKILINK_REGEX.source, "g")

  let match: RegExpExecArray | null
  while ((match = regex.exec(content)) !== null) {
    const [full, target, label] = match
    links.push(parseWikilink(full))
  }

  return links
}

/**
 * Convert a file path to display format (removes .md extension).
 */
export function pathToDisplayPath(relativePath: string): string {
  if (relativePath.endsWith(".md")) {
    return relativePath.slice(0, -3)
  }
  return relativePath
}
