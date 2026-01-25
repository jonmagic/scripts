import { describe, expect, test } from "bun:test"
import {
  serializeFrontmatter,
  addFrontmatterToContent,
  type FrontmatterData,
} from "./serialize.js"

describe("serializeFrontmatter", () => {
  test("serializes required fields", () => {
    const fm: FrontmatterData = {
      uid: "3lz7nwvh4zc2u",
      type: "daily.project",
      created: "2026-01-24T00:00:00.000Z",
    }
    const result = serializeFrontmatter(fm)

    expect(result).toBe(`---
uid: 3lz7nwvh4zc2u
type: daily.project
created: 2026-01-24T00:00:00.000Z
---`)
  })

  test("includes updated when present", () => {
    const fm: FrontmatterData = {
      uid: "abc",
      type: "daily.project",
      created: "2026-01-01T00:00:00.000Z",
      updated: "2026-01-24T12:00:00.000Z",
    }
    const result = serializeFrontmatter(fm)

    expect(result).toContain("updated: 2026-01-24T12:00:00.000Z")
  })

  test("omits updated when not present", () => {
    const fm: FrontmatterData = {
      uid: "abc",
      type: "daily.project",
      created: "2026-01-01T00:00:00.000Z",
    }
    const result = serializeFrontmatter(fm)

    expect(result).not.toContain("updated:")
  })

  test("serializes tags array", () => {
    const fm: FrontmatterData = {
      uid: "abc",
      type: "daily.project",
      created: "2026-01-01T00:00:00.000Z",
      tags: ["foo", "bar", "baz"],
    }
    const result = serializeFrontmatter(fm)

    expect(result).toContain("tags: [foo, bar, baz]")
  })

  test("omits empty tags array", () => {
    const fm: FrontmatterData = {
      uid: "abc",
      type: "daily.project",
      created: "2026-01-01T00:00:00.000Z",
      tags: [],
    }
    const result = serializeFrontmatter(fm)

    expect(result).not.toContain("tags:")
  })

  test("serializes links block", () => {
    const fm: FrontmatterData = {
      uid: "abc",
      type: "daily.project",
      created: "2026-01-01T00:00:00.000Z",
      links: {
        parent: ["uid1", "uid2"],
        related: ["uid3"],
      },
    }
    const result = serializeFrontmatter(fm)

    expect(result).toContain("links:")
    expect(result).toContain("  parent: [uid1, uid2]")
    expect(result).toContain("  related: [uid3]")
  })

  test("omits links block when all arrays empty", () => {
    const fm: FrontmatterData = {
      uid: "abc",
      type: "daily.project",
      created: "2026-01-01T00:00:00.000Z",
      links: {
        parent: [],
        related: [],
      },
    }
    const result = serializeFrontmatter(fm)

    expect(result).not.toContain("links:")
  })
})

describe("addFrontmatterToContent", () => {
  test("adds frontmatter to content without it", () => {
    const content = `# My Note

Some content here.`
    const fm: FrontmatterData = {
      uid: "3lz7nwvh4zc2u",
      type: "daily.project",
      created: "2026-01-24T00:00:00.000Z",
    }

    const result = addFrontmatterToContent(content, fm)

    expect(result).toBe(`---
uid: 3lz7nwvh4zc2u
type: daily.project
created: 2026-01-24T00:00:00.000Z
---

# My Note

Some content here.`)
  })

  test("returns original content if already has frontmatter", () => {
    const content = `---
uid: existing
---

# My Note`
    const fm: FrontmatterData = {
      uid: "new-uid",
      type: "daily.project",
      created: "2026-01-24T00:00:00.000Z",
    }

    const result = addFrontmatterToContent(content, fm)

    expect(result).toBe(content)
  })

  test("handles Windows line endings in existing frontmatter", () => {
    const content = "---\r\nuid: existing\r\n---\r\n\r\n# My Note"
    const fm: FrontmatterData = {
      uid: "new-uid",
      type: "daily.project",
      created: "2026-01-24T00:00:00.000Z",
    }

    const result = addFrontmatterToContent(content, fm)

    expect(result).toBe(content)
  })

  test("handles empty content", () => {
    const fm: FrontmatterData = {
      uid: "abc",
      type: "daily.project",
      created: "2026-01-24T00:00:00.000Z",
    }

    const result = addFrontmatterToContent("", fm)

    expect(result).toContain("uid: abc")
    expect(result).toEndWith("---\n\n")
  })
})
