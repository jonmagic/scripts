/// <reference types="bun-types" />

import { describe, expect, test } from "bun:test"
import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

import { createBookmark, slugifyTitle, titleFromUrl } from "./createBookmark.js"

describe("slugifyTitle", () => {
  test("lowercases and preserves spaces", () => {
    expect(slugifyTitle("My Great Article")).toBe("my great article")
  })

  test("strips unsafe filesystem characters", () => {
    expect(slugifyTitle('What: "Is" This?')).toBe("what is this")
  })

  test("collapses multiple spaces", () => {
    expect(slugifyTitle("too   many    spaces")).toBe("too many spaces")
  })

  test("replaces slashes with hyphens", () => {
    expect(slugifyTitle("foo/bar\\baz")).toBe("foo-bar-baz")
  })
})

describe("titleFromUrl", () => {
  test("extracts last path segment", () => {
    expect(titleFromUrl("https://example.com/blog/my-great-post")).toBe(
      "my great post"
    )
  })

  test("strips file extensions", () => {
    expect(titleFromUrl("https://example.com/doc/readme.html")).toBe("readme")
  })

  test("falls back to hostname when no path", () => {
    expect(titleFromUrl("https://example.com/")).toBe("example.com")
    expect(titleFromUrl("https://www.example.com")).toBe("example.com")
  })

  test("handles invalid URLs gracefully", () => {
    expect(titleFromUrl("not-a-url")).toBe("untitled bookmark")
  })

  test("converts underscores and hyphens to spaces", () => {
    expect(titleFromUrl("https://example.com/my_cool-article")).toBe(
      "my cool article"
    )
  })
})

describe("createBookmark", () => {
  test("creates a numbered file under Bookmarks/YYYY-MM-DD", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const r1 = await createBookmark({
      url: "https://example.com/first-article",
      title: "First Article",
      brainRoot: tmp,
      date,
    })

    expect(r1.number).toBe(1)
    expect(r1.filePath).toEndWith(
      path.join("Bookmarks", "2026-02-13", "01 first article.md")
    )
    expect(r1.url).toBe("https://example.com/first-article")
    expect(r1.title).toBe("First Article")

    const r2 = await createBookmark({
      url: "https://example.com/second",
      title: "Second Article",
      brainRoot: tmp,
      date,
    })
    expect(r2.number).toBe(2)
  })

  test("includes frontmatter with uid, type, url, title", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://ntietz.com/blog/engineering-notebook/",
      title: "Using an Engineering Notebook",
      brainRoot: tmp,
      date,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toStartWith("---\n")
    expect(content).toContain("uid: ")
    expect(content).toContain("type: bookmark")
    expect(content).toContain("created: 2026-02-13T00:00:00Z")
    expect(content).toContain(
      "url: https://ntietz.com/blog/engineering-notebook/"
    )
    expect(content).toContain('title: "Using an Engineering Notebook"')
    expect(result.uid).toBeTruthy()
    expect(result.uid.length).toBe(13)
  })

  test("includes source when provided", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://example.com/article",
      title: "Test Article",
      source: "hacker-news",
      brainRoot: tmp,
      date,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toContain("source: hacker-news")
  })

  test("includes tags when provided", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://example.com/article",
      title: "Tagged Article",
      tags: ["pkm", "architecture"],
      brainRoot: tmp,
      date,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toContain("tags: [pkm, architecture]")
  })

  test("includes blurb as markdown body", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://example.com/article",
      title: "Article With Blurb",
      blurb: "This is a great article about testing.",
      brainRoot: tmp,
      date,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toContain("---\n\nThis is a great article about testing.\n")
  })

  test("omits body when no blurb provided", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://example.com/article",
      title: "No Blurb",
      brainRoot: tmp,
      date,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toEndWith("---\n")
  })

  test("derives title from URL when not provided", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://example.com/blog/my-great-post",
      brainRoot: tmp,
      date,
    })

    expect(result.title).toBe("my great post")
    expect(result.filePath).toEndWith("01 my great post.md")
  })

  test("escapes double quotes in title", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://example.com/article",
      title: 'The "Best" Article',
      brainRoot: tmp,
      date,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toContain('title: "The \\"Best\\" Article"')
  })

  test("throws on empty URL", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))

    expect(
      createBookmark({ url: "", brainRoot: tmp })
    ).rejects.toThrow("URL is required")
  })

  test("omits source and tags when not provided", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 1, 13, 12, 0, 0)

    const result = await createBookmark({
      url: "https://example.com/minimal",
      title: "Minimal Bookmark",
      brainRoot: tmp,
      date,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).not.toContain("source:")
    expect(content).not.toContain("tags:")
  })
})
