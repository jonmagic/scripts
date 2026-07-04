import { describe, expect, test } from "bun:test"
import {
  rankRecentBrainFiles,
  type RecentBrainFileCandidate,
} from "../src/commands/recentBrainFileRanking.js"

function candidate(
  relativePath: string,
  mtime: number
): RecentBrainFileCandidate {
  return {
    absolutePath: `/Brain/${relativePath}`,
    relativePath,
    mtime,
  }
}

describe("rankRecentBrainFiles", () => {
  test("puts git-modified files before newer unmodified files", () => {
    const files = [
      candidate("Daily Projects/2026-07-04/01 new.md", 300),
      candidate("Weekly Notes/Week of 2026-06-28.md", 100),
      candidate("Projects/example/references.md", 200),
    ]
    const statuses = new Map([
      ["Weekly Notes/Week of 2026-06-28.md", "M"],
      ["Projects/example/references.md", "??"],
    ])

    expect(
      rankRecentBrainFiles(files, statuses, 10).map((file) => [
        file.relativePath,
        file.gitStatus,
      ])
    ).toEqual([
      ["Projects/example/references.md", "??"],
      ["Weekly Notes/Week of 2026-06-28.md", "M"],
      ["Daily Projects/2026-07-04/01 new.md", null],
    ])
  })

  test("falls back to mtime and path for deterministic ordering", () => {
    const files = [
      candidate("z.md", 100),
      candidate("a.md", 100),
      candidate("new.md", 200),
    ]

    expect(
      rankRecentBrainFiles(files, new Map(), 10).map(
        (file) => file.relativePath
      )
    ).toEqual(["new.md", "a.md", "z.md"])
  })

  test("respects the limit", () => {
    const files = [candidate("1.md", 300), candidate("2.md", 200)]

    expect(rankRecentBrainFiles(files, new Map(), 1)).toHaveLength(1)
  })
})
