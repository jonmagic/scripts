// Wikilink resolution - resolves link targets to file paths.

import { UID_PREFIX } from "./patterns.js"
import type { UidIndex } from "./uidIndex.js"

/**
 * Resolve a wikilink target to a file path.
 *
 * @param target The link target (e.g., "uid:xxx" or "Meeting Notes/tgthorley")
 * @param index The UID index for looking up UID links
 * @param allPaths All known relative paths in the workspace (for path matching)
 * @returns The resolved relative path, or null if not found
 */
export function resolveWikilink(
  target: string,
  index: UidIndex,
  allPaths: string[]
): string | null {
  // UID-based link
  if (target.startsWith(UID_PREFIX)) {
    const uid = target.slice(UID_PREFIX.length)
    return index.byUid.get(uid) ?? null
  }

  // Path-based link - try various matching strategies
  return resolvePath(target, allPaths)
}

/**
 * Resolve a path-based wikilink target.
 * Supports:
 * - Exact match (with or without .md)
 * - Short ref (filename only)
 * - Case-insensitive matching
 */
function resolvePath(target: string, allPaths: string[]): string | null {
  const targetLower = target.toLowerCase()
  const targetWithMd = targetLower.endsWith(".md") ? targetLower : targetLower + ".md"
  const targetWithoutMd = targetLower.endsWith(".md")
    ? targetLower.slice(0, -3)
    : targetLower

  // 1. Exact match (case-insensitive)
  for (const path of allPaths) {
    const pathLower = path.toLowerCase()
    if (pathLower === targetWithMd || pathLower === targetWithoutMd) {
      return path
    }
  }

  // 2. Path ends with target (for partial paths like "tgthorley" matching "Meeting Notes/tgthorley.md")
  for (const path of allPaths) {
    const pathLower = path.toLowerCase()
    // Check if path ends with /target.md or /target
    if (
      pathLower.endsWith("/" + targetWithMd) ||
      pathLower.endsWith("/" + targetWithoutMd + ".md")
    ) {
      return path
    }
  }

  // 3. Filename match (short ref)
  const targetFilename = getFilename(targetWithoutMd).toLowerCase()
  const matches: string[] = []

  for (const path of allPaths) {
    const pathFilename = getFilename(path).toLowerCase()
    // Remove .md for comparison
    const pathNameNoExt = pathFilename.endsWith(".md")
      ? pathFilename.slice(0, -3)
      : pathFilename

    if (pathNameNoExt === targetFilename) {
      matches.push(path)
    }
  }

  // If exactly one match, return it
  if (matches.length === 1) {
    const match = matches[0]
    return match !== undefined ? match : null
  }

  // Multiple matches - can't resolve unambiguously
  // Could return first or null; we'll return null for safety
  return null
}

/**
 * Get filename from a path.
 */
function getFilename(path: string): string {
  const lastSlash = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
  return lastSlash === -1 ? path : path.slice(lastSlash + 1)
}
