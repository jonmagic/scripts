// Frontmatter parsing utilities for Brain markdown files.

export interface ParsedFrontmatter {
  uid?: string
  type?: string
  created?: string
  updated?: string
  tags?: string[]
  links?: {
    parent?: string[]
    source?: string[]
    related?: string[]
  }
  [key: string]: unknown
}

export interface ParseResult {
  frontmatter: ParsedFrontmatter | null
  body: string
}

/**
 * Check if content starts with YAML frontmatter delimiter.
 */
export function hasFrontmatter(content: string): boolean {
  return content.startsWith("---\n") || content.startsWith("---\r\n")
}

/**
 * Parse YAML frontmatter from markdown content.
 * Returns the parsed frontmatter object and the remaining body.
 */
export function parseFrontmatter(content: string): ParseResult {
  if (!hasFrontmatter(content)) {
    return { frontmatter: null, body: content }
  }

  const lines = content.split(/\r?\n/)
  let endIndex = -1

  // Find closing delimiter (skip first line which is opening ---)
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i]
    if (line !== undefined && line.trim() === "---") {
      endIndex = i
      break
    }
  }

  if (endIndex === -1) {
    // Malformed: no closing delimiter
    return { frontmatter: null, body: content }
  }

  const frontmatterLines = lines.slice(1, endIndex)
  const body = lines
    .slice(endIndex + 1)
    .join("\n")
    .replace(/^\n+/, "")

  // Simple YAML parsing for our known structure
  const frontmatter: ParsedFrontmatter = {}
  let inLinks = false

  for (const line of frontmatterLines) {
    // Skip empty lines
    if (!line.trim()) continue

    // Check for nested links block
    if (line === "links:") {
      frontmatter.links = {}
      inLinks = true
      continue
    }

    // Handle indented link arrays (e.g., "  parent: [uid1, uid2]")
    if (inLinks && line.startsWith("  ")) {
      const trimmed = line.trim()
      const colonIdx = trimmed.indexOf(":")
      if (colonIdx !== -1) {
        const key = trimmed.slice(0, colonIdx).trim()
        const value = trimmed.slice(colonIdx + 1).trim()
        if (value.startsWith("[") && value.endsWith("]")) {
          const items = value
            .slice(1, -1)
            .split(",")
            .map((s) => s.trim())
            .filter((s) => s.length > 0)
          ;(frontmatter.links as Record<string, string[]>)[key] = items
        }
      }
      continue
    } else if (line.startsWith("  ")) {
      // Other indented content - skip for now
      continue
    }

    inLinks = false

    const colonIdx = line.indexOf(":")
    if (colonIdx === -1) continue

    const key = line.slice(0, colonIdx).trim()
    let value = line.slice(colonIdx + 1).trim()

    // Remove quotes if present
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1)
    }

    // Handle inline arrays like "tags: [foo, bar]"
    if (value.startsWith("[") && value.endsWith("]")) {
      const items = value
        .slice(1, -1)
        .split(",")
        .map((s) => s.trim())
        .filter((s) => s.length > 0)
      frontmatter[key] = items
    } else if (value === "") {
      // Could be start of a block, we'll handle simple cases
      frontmatter[key] = value
    } else {
      frontmatter[key] = value
    }
  }

  return { frontmatter, body }
}

/**
 * Extract the UID from markdown content's frontmatter.
 * Returns null if no frontmatter or no uid field.
 */
export function extractUid(content: string): string | null {
  const { frontmatter } = parseFrontmatter(content)
  return frontmatter?.uid ?? null
}
