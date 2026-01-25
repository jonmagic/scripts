import { describe, expect, test } from "bun:test"
import { hasFrontmatter, parseFrontmatter, extractUid } from "./parse.js"

describe("hasFrontmatter", () => {
  test("returns true for content with frontmatter", () => {
    const content = `---
uid: abc123
---

# Title`
    expect(hasFrontmatter(content)).toBe(true)
  })

  test("returns false for content without frontmatter", () => {
    const content = `# Title

Some content`
    expect(hasFrontmatter(content)).toBe(false)
  })

  test("returns false for empty content", () => {
    expect(hasFrontmatter("")).toBe(false)
  })

  test("handles Windows line endings", () => {
    const content = "---\r\nuid: abc\r\n---\r\n"
    expect(hasFrontmatter(content)).toBe(true)
  })
})

describe("parseFrontmatter", () => {
  test("parses basic frontmatter fields", () => {
    const content = `---
uid: 3lz7nwvh4zc2u
type: daily.project
created: 2026-01-24T00:00:00.000Z
---

# My Note`
    const { frontmatter, body } = parseFrontmatter(content)

    expect(frontmatter).not.toBeNull()
    expect(frontmatter?.uid).toBe("3lz7nwvh4zc2u")
    expect(frontmatter?.type).toBe("daily.project")
    expect(frontmatter?.created).toBe("2026-01-24T00:00:00.000Z")
    expect(body).toBe("# My Note")
  })

  test("returns null frontmatter for content without it", () => {
    const content = `# Just a title`
    const { frontmatter, body } = parseFrontmatter(content)

    expect(frontmatter).toBeNull()
    expect(body).toBe("# Just a title")
  })

  test("handles malformed frontmatter (no closing delimiter)", () => {
    const content = `---
uid: abc123
# Missing closing delimiter`
    const { frontmatter, body } = parseFrontmatter(content)

    expect(frontmatter).toBeNull()
    expect(body).toBe(content)
  })

  test("parses inline arrays", () => {
    const content = `---
uid: abc
tags: [foo, bar, baz]
---

Content`
    const { frontmatter } = parseFrontmatter(content)

    expect(frontmatter?.tags).toEqual(["foo", "bar", "baz"])
  })

  test("parses empty inline arrays", () => {
    const content = `---
uid: abc
tags: []
---

Content`
    const { frontmatter } = parseFrontmatter(content)

    expect(frontmatter?.tags).toEqual([])
  })

  test("parses links block", () => {
    const content = `---
uid: abc
links:
  parent: [uid1, uid2]
  related: [uid3]
---

Content`
    const { frontmatter } = parseFrontmatter(content)

    expect(frontmatter?.links).toEqual({
      parent: ["uid1", "uid2"],
      related: ["uid3"],
    })
  })

  test("handles quoted values", () => {
    const content = `---
uid: "quoted-uid"
type: 'single-quoted'
---

Content`
    const { frontmatter } = parseFrontmatter(content)

    expect(frontmatter?.uid).toBe("quoted-uid")
    expect(frontmatter?.type).toBe("single-quoted")
  })

  test("strips leading newlines from body", () => {
    const content = `---
uid: abc
---


# Title with blank lines before`
    const { body } = parseFrontmatter(content)

    expect(body).toBe("# Title with blank lines before")
  })

  test("handles optional updated field", () => {
    const content = `---
uid: abc
created: 2026-01-01T00:00:00.000Z
updated: 2026-01-24T12:00:00.000Z
---

Content`
    const { frontmatter } = parseFrontmatter(content)

    expect(frontmatter?.created).toBe("2026-01-01T00:00:00.000Z")
    expect(frontmatter?.updated).toBe("2026-01-24T12:00:00.000Z")
  })
})

describe("extractUid", () => {
  test("extracts uid from valid frontmatter", () => {
    const content = `---
uid: 3lz7nwvh4zc2u
type: daily.project
---

Content`
    expect(extractUid(content)).toBe("3lz7nwvh4zc2u")
  })

  test("returns null when no frontmatter", () => {
    const content = `# Just content`
    expect(extractUid(content)).toBeNull()
  })

  test("returns null when frontmatter has no uid", () => {
    const content = `---
type: daily.project
---

Content`
    expect(extractUid(content)).toBeNull()
  })
})
