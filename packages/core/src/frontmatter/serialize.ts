// Frontmatter serialization utilities for Brain markdown files.

export interface FrontmatterData {
  uid: string
  type: string
  created: string
  updated?: string
  tags?: string[]
  /** Agent session resume command (e.g. "opencode -s ses_abc123"). */
  session?: string
  /** Bookmark URL. */
  url?: string
  /** Page title (auto-fetched or manual). */
  title?: string
  /** Where the bookmark was found (e.g. "hacker-news", "slack", "colleague"). */
  source?: string
  links?: {
    parent?: string[]
    source?: string[]
    related?: string[]
  }
}

/**
 * Serialize frontmatter data to YAML string (including delimiters).
 */
export function serializeFrontmatter(fm: FrontmatterData): string {
  const lines: string[] = ["---"]

  lines.push(`uid: ${fm.uid}`)
  lines.push(`type: ${fm.type}`)
  lines.push(`created: ${fm.created}`)

  if (fm.updated) {
    lines.push(`updated: ${fm.updated}`)
  }

  if (fm.tags && fm.tags.length > 0) {
    lines.push(`tags: [${fm.tags.join(", ")}]`)
  }

  if (fm.session) {
    lines.push(`session: ${fm.session}`)
  }

  if (fm.url) {
    lines.push(`url: ${fm.url}`)
  }

  if (fm.title) {
    lines.push(`title: "${fm.title.replace(/"/g, '\\"')}"`)
  }

  if (fm.source) {
    lines.push(`source: ${fm.source}`)
  }

  if (fm.links) {
    const hasLinks = Object.values(fm.links).some(
      (arr) => arr && arr.length > 0
    )
    if (hasLinks) {
      lines.push("links:")
      for (const [key, values] of Object.entries(fm.links)) {
        if (values && values.length > 0) {
          lines.push(`  ${key}: [${values.join(", ")}]`)
        }
      }
    }
  }

  lines.push("---")
  return lines.join("\n")
}

/**
 * Add frontmatter to content that doesn't have it.
 * If content already has frontmatter, returns original content unchanged.
 */
export function addFrontmatterToContent(
  content: string,
  fm: FrontmatterData
): string {
  // Check if already has frontmatter
  if (content.startsWith("---\n") || content.startsWith("---\r\n")) {
    return content
  }

  const serialized = serializeFrontmatter(fm)
  return serialized + "\n\n" + content
}
