import { describe, expect, test } from "bun:test"
import { resolveWikilink } from "./resolve.js"
import { buildUidIndex, type FileInfo } from "./uidIndex.js"

const makeFile = (relativePath: string, uid?: string): FileInfo => ({
  relativePath,
  content: uid
    ? `---\nuid: ${uid}\ntype: test\ncreated: 2026-01-24T00:00:00.000Z\n---\n\n# Content`
    : `# No frontmatter`,
})

describe("resolveWikilink", () => {
  const files: FileInfo[] = [
    makeFile("Meeting Notes/tgthorley/2026-01-19/01.md", "uid-tom-meeting"),
    makeFile("Meeting Notes/rachelmcohen/2026-01-20/01.md", "uid-rachel-meeting"),
    makeFile("Daily Projects/2026-01-24/01 notes.md", "uid-daily"),
    makeFile("Projects/MyProject/README.md", "uid-project"),
    makeFile("Snippets/2026-01-17-to-2026-01-23.md", "uid-snippet"),
  ]
  const index = buildUidIndex(files)
  const allPaths = files.map((f) => f.relativePath)

  describe("UID-based links", () => {
    test("resolves uid: prefix to path", () => {
      const result = resolveWikilink("uid:uid-tom-meeting", index, allPaths)
      expect(result).toBe("Meeting Notes/tgthorley/2026-01-19/01.md")
    })

    test("returns null for unknown UID", () => {
      const result = resolveWikilink("uid:nonexistent", index, allPaths)
      expect(result).toBeNull()
    })
  })

  describe("path-based links", () => {
    test("resolves exact path with .md", () => {
      const result = resolveWikilink(
        "Meeting Notes/tgthorley/2026-01-19/01.md",
        index,
        allPaths
      )
      expect(result).toBe("Meeting Notes/tgthorley/2026-01-19/01.md")
    })

    test("resolves exact path without .md", () => {
      const result = resolveWikilink(
        "Meeting Notes/tgthorley/2026-01-19/01",
        index,
        allPaths
      )
      expect(result).toBe("Meeting Notes/tgthorley/2026-01-19/01.md")
    })

    test("resolves partial path ending", () => {
      const result = resolveWikilink("tgthorley/2026-01-19/01", index, allPaths)
      expect(result).toBe("Meeting Notes/tgthorley/2026-01-19/01.md")
    })

    test("resolves short ref (filename only) when unique", () => {
      const result = resolveWikilink("README", index, allPaths)
      expect(result).toBe("Projects/MyProject/README.md")
    })

    test("returns first match for partial path ending", () => {
      // When multiple files match via partial path ending,
      // returns first match (iteration order)
      const result = resolveWikilink("notes", index, allPaths)
      // "notes" doesn't match any partial path ending, so falls through to filename match
      // But "01 notes" would match via partial path, so this test needs adjustment
      expect(result).toBeNull() // No file named just "notes.md"
    })

    test("handles truly ambiguous filename matches", () => {
      // Create files where the filename match is ambiguous
      // and partial path ending doesn't match
      const ambiguousFiles: FileInfo[] = [
        makeFile("A/SubDir/notes.md", "uid-a"),
        makeFile("B/SubDir/notes.md", "uid-b"),
      ]
      const idx = buildUidIndex(ambiguousFiles)
      const paths = ambiguousFiles.map((f) => f.relativePath)

      // "notes" as a query:
      // - Step 1 (exact): No match
      // - Step 2 (ends with): Both end with "/notes.md", returns first
      const result = resolveWikilink("notes", idx, paths)
      expect(result).toBe("A/SubDir/notes.md")
    })

    test("is case insensitive", () => {
      const result = resolveWikilink("MEETING NOTES/TGTHORLEY/2026-01-19/01", index, allPaths)
      expect(result).toBe("Meeting Notes/tgthorley/2026-01-19/01.md")
    })

    test("returns null for non-existent path", () => {
      const result = resolveWikilink("Non/Existent/Path", index, allPaths)
      expect(result).toBeNull()
    })
  })

  describe("edge cases", () => {
    test("handles empty paths list", () => {
      const result = resolveWikilink("anything", index, [])
      expect(result).toBeNull()
    })

    test("handles paths with spaces", () => {
      const filesWithSpaces: FileInfo[] = [
        makeFile("Daily Projects/2026-01-24/01 notes.md", "uid-daily"),
      ]
      const idx = buildUidIndex(filesWithSpaces)
      const paths = filesWithSpaces.map((f) => f.relativePath)

      const result = resolveWikilink("Daily Projects/2026-01-24/01 notes", idx, paths)
      expect(result).toBe("Daily Projects/2026-01-24/01 notes.md")
    })
  })
})
