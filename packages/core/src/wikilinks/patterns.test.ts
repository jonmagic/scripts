import { describe, expect, test } from "bun:test"
import {
  WIKILINK_REGEX,
  parseWikilink,
  formatWikilink,
  extractWikilinks,
  pathToDisplayPath,
} from "./patterns.js"

describe("WIKILINK_REGEX", () => {
  test("matches simple path link", () => {
    const content = "See [[Meeting Notes/tgthorley]] for details"
    const matches = [...content.matchAll(WIKILINK_REGEX)]

    expect(matches.length).toBe(1)
    expect(matches[0][0]).toBe("[[Meeting Notes/tgthorley]]")
    expect(matches[0][1]).toBe("Meeting Notes/tgthorley")
    expect(matches[0][2]).toBeUndefined()
  })

  test("matches path link with label", () => {
    const content = "See [[Meeting Notes/tgthorley|Tom's Notes]] for details"
    const matches = [...content.matchAll(WIKILINK_REGEX)]

    expect(matches.length).toBe(1)
    expect(matches[0][1]).toBe("Meeting Notes/tgthorley")
    expect(matches[0][2]).toBe("Tom's Notes")
  })

  test("matches UID link", () => {
    const content = "Link to [[uid:3lz7nwvh4zc2u|Meeting Notes/tgthorley/2026-01-19/01]]"
    const matches = [...content.matchAll(WIKILINK_REGEX)]

    expect(matches.length).toBe(1)
    expect(matches[0][1]).toBe("uid:3lz7nwvh4zc2u")
    expect(matches[0][2]).toBe("Meeting Notes/tgthorley/2026-01-19/01")
  })

  test("matches multiple links", () => {
    const content = "See [[FileA]] and [[FileB|B Label]] and [[uid:abc|FileC]]"
    const matches = [...content.matchAll(WIKILINK_REGEX)]

    expect(matches.length).toBe(3)
  })

  test("does not match incomplete brackets", () => {
    const content = "Not a link: [single bracket] or [[unclosed"
    const matches = [...content.matchAll(WIKILINK_REGEX)]

    expect(matches.length).toBe(0)
  })
})

describe("parseWikilink", () => {
  test("parses simple path link", () => {
    const result = parseWikilink("[[Meeting Notes/tgthorley]]")

    expect(result.target).toBe("Meeting Notes/tgthorley")
    expect(result.label).toBeUndefined()
    expect(result.isUid).toBe(false)
    expect(result.uid).toBeUndefined()
  })

  test("parses path link with label", () => {
    const result = parseWikilink("[[Meeting Notes/tgthorley|Tom]]")

    expect(result.target).toBe("Meeting Notes/tgthorley")
    expect(result.label).toBe("Tom")
    expect(result.isUid).toBe(false)
  })

  test("parses UID link", () => {
    const result = parseWikilink("[[uid:3lz7nwvh4zc2u|Meeting Notes/tgthorley]]")

    expect(result.target).toBe("uid:3lz7nwvh4zc2u")
    expect(result.label).toBe("Meeting Notes/tgthorley")
    expect(result.isUid).toBe(true)
    expect(result.uid).toBe("3lz7nwvh4zc2u")
  })

  test("handles inner content without brackets", () => {
    const result = parseWikilink("Meeting Notes/tgthorley")

    expect(result.target).toBe("Meeting Notes/tgthorley")
    expect(result.full).toBe("[[Meeting Notes/tgthorley]]")
  })
})

describe("formatWikilink", () => {
  test("formats UID link", () => {
    const result = formatWikilink("3lz7nwvh4zc2u", "Meeting Notes/tgthorley/2026-01-19/01")

    expect(result).toBe("[[uid:3lz7nwvh4zc2u|Meeting Notes/tgthorley/2026-01-19/01]]")
  })

  test("formats path link when uid is null", () => {
    const result = formatWikilink(null, "Meeting Notes/tgthorley")

    expect(result).toBe("[[Meeting Notes/tgthorley]]")
  })
})

describe("extractWikilinks", () => {
  test("extracts all wikilinks from content", () => {
    const content = `# My Note

See [[Meeting Notes/tgthorley]] and also [[uid:abc123|Daily Projects/2026-01-24/01]].

Another link: [[Projects/MyProject|Project Docs]]`

    const links = extractWikilinks(content)

    expect(links.length).toBe(3)
    expect(links[0].target).toBe("Meeting Notes/tgthorley")
    expect(links[0].isUid).toBe(false)
    expect(links[1].target).toBe("uid:abc123")
    expect(links[1].isUid).toBe(true)
    expect(links[1].uid).toBe("abc123")
    expect(links[2].target).toBe("Projects/MyProject")
    expect(links[2].label).toBe("Project Docs")
  })

  test("returns empty array for content without links", () => {
    const content = "Just plain text"
    const links = extractWikilinks(content)

    expect(links.length).toBe(0)
  })
})

describe("pathToDisplayPath", () => {
  test("removes .md extension", () => {
    expect(pathToDisplayPath("Meeting Notes/tgthorley.md")).toBe("Meeting Notes/tgthorley")
  })

  test("leaves non-.md paths unchanged", () => {
    expect(pathToDisplayPath("images/screenshot.png")).toBe("images/screenshot.png")
  })

  test("handles paths without extension", () => {
    expect(pathToDisplayPath("Meeting Notes/tgthorley")).toBe("Meeting Notes/tgthorley")
  })
})
