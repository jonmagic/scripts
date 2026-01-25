// UID index builder for wikilink resolution.

import { extractUid } from "../frontmatter/parse.js"

/**
 * A bidirectional index mapping UIDs to paths and paths to UIDs.
 */
export interface UidIndex {
  /** Map from UID to absolute or relative path */
  byUid: Map<string, string>
  /** Map from relative path (without .md) to UID */
  byPath: Map<string, string>
}

/**
 * File info needed to build the index.
 */
export interface FileInfo {
  /** Relative path from workspace root */
  relativePath: string
  /** File content (for extracting UID from frontmatter) */
  content: string
}

/**
 * Build a UID index from a list of files.
 * @param files Array of file info objects with relativePath and content
 * @returns UidIndex for bidirectional lookup
 */
export function buildUidIndex(files: FileInfo[]): UidIndex {
  const byUid = new Map<string, string>()
  const byPath = new Map<string, string>()

  for (const file of files) {
    const uid = extractUid(file.content)
    if (uid) {
      byUid.set(uid, file.relativePath)

      // Store path without .md extension for easier matching
      const pathKey = file.relativePath.endsWith(".md")
        ? file.relativePath.slice(0, -3)
        : file.relativePath
      byPath.set(pathKey, uid)

      // Also store with .md for exact matches
      byPath.set(file.relativePath, uid)
    }
  }

  return { byUid, byPath }
}

/**
 * Look up a path by UID.
 */
export function getPathByUid(index: UidIndex, uid: string): string | undefined {
  return index.byUid.get(uid)
}

/**
 * Look up a UID by path.
 * @param path The relative path (with or without .md extension)
 */
export function getUidByPath(index: UidIndex, path: string): string | undefined {
  // Try exact match first
  const exact = index.byPath.get(path)
  if (exact) return exact

  // Try without .md
  if (path.endsWith(".md")) {
    return index.byPath.get(path.slice(0, -3))
  }

  // Try with .md
  return index.byPath.get(path + ".md")
}
