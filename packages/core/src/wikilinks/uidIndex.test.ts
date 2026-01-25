import { describe, expect, test } from "bun:test"
import {
  buildUidIndex,
  getPathByUid,
  getUidByPath,
  type FileInfo,
} from "./uidIndex.js"

const makeFile = (relativePath: string, uid?: string): FileInfo => ({
  relativePath,
  content: uid
    ? `---\nuid: ${uid}\ntype: test\ncreated: 2026-01-24T00:00:00.000Z\n---\n\n# Content`
    : `# No frontmatter`,
})

describe("buildUidIndex", () => {
  test("builds index from files with UIDs", () => {
    const files: FileInfo[] = [
      makeFile("Meeting Notes/tgthorley.md", "uid-tom"),
      makeFile("Daily Projects/2026-01-24/01 notes.md", "uid-daily"),
      makeFile("Projects/MyProject/README.md", "uid-project"),
    ]

    const index = buildUidIndex(files)

    expect(index.byUid.size).toBe(3)
    expect(index.byUid.get("uid-tom")).toBe("Meeting Notes/tgthorley.md")
    expect(index.byUid.get("uid-daily")).toBe("Daily Projects/2026-01-24/01 notes.md")
    expect(index.byUid.get("uid-project")).toBe("Projects/MyProject/README.md")
  })

  test("handles files without UIDs", () => {
    const files: FileInfo[] = [
      makeFile("Meeting Notes/tgthorley.md", "uid-tom"),
      makeFile("Meeting Notes/no-frontmatter.md"), // no UID
    ]

    const index = buildUidIndex(files)

    expect(index.byUid.size).toBe(1)
    expect(index.byUid.has("uid-tom")).toBe(true)
  })

  test("builds path-to-uid mapping without .md extension", () => {
    const files: FileInfo[] = [
      makeFile("Meeting Notes/tgthorley.md", "uid-tom"),
    ]

    const index = buildUidIndex(files)

    expect(index.byPath.get("Meeting Notes/tgthorley")).toBe("uid-tom")
    expect(index.byPath.get("Meeting Notes/tgthorley.md")).toBe("uid-tom")
  })

  test("handles empty file list", () => {
    const index = buildUidIndex([])

    expect(index.byUid.size).toBe(0)
    expect(index.byPath.size).toBe(0)
  })
})

describe("getPathByUid", () => {
  test("returns path for existing UID", () => {
    const files: FileInfo[] = [
      makeFile("Meeting Notes/tgthorley.md", "uid-tom"),
    ]
    const index = buildUidIndex(files)

    expect(getPathByUid(index, "uid-tom")).toBe("Meeting Notes/tgthorley.md")
  })

  test("returns undefined for missing UID", () => {
    const index = buildUidIndex([])

    expect(getPathByUid(index, "nonexistent")).toBeUndefined()
  })
})

describe("getUidByPath", () => {
  test("returns UID for path with .md extension", () => {
    const files: FileInfo[] = [
      makeFile("Meeting Notes/tgthorley.md", "uid-tom"),
    ]
    const index = buildUidIndex(files)

    expect(getUidByPath(index, "Meeting Notes/tgthorley.md")).toBe("uid-tom")
  })

  test("returns UID for path without .md extension", () => {
    const files: FileInfo[] = [
      makeFile("Meeting Notes/tgthorley.md", "uid-tom"),
    ]
    const index = buildUidIndex(files)

    expect(getUidByPath(index, "Meeting Notes/tgthorley")).toBe("uid-tom")
  })

  test("returns undefined for missing path", () => {
    const index = buildUidIndex([])

    expect(getUidByPath(index, "nonexistent")).toBeUndefined()
  })
})
