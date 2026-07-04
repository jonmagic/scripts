import { afterEach, describe, expect, test } from "bun:test"
import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

import {
  getBrainCollectionCandidates,
  getBrainCollectionEmptyMessage,
} from "../src/commands/brainCollectionQuickPickCandidates.js"

let tempRoots: string[] = []

async function createTempBrain(): Promise<string> {
  const tempRoot = await fs.mkdtemp(
    path.join(os.tmpdir(), "brain-quick-picks-test-")
  )
  tempRoots.push(tempRoot)
  return tempRoot
}

async function writeBrainFile(
  brainRoot: string,
  relativePath: string
): Promise<void> {
  const absolutePath = path.join(brainRoot, relativePath)
  await fs.mkdir(path.dirname(absolutePath), { recursive: true })
  await fs.writeFile(absolutePath, "# Test\n")
}

afterEach(async () => {
  await Promise.all(
    tempRoots.map((tempRoot) =>
      fs.rm(tempRoot, { recursive: true, force: true })
    )
  )
  tempRoots = []
})

describe("getBrainCollectionCandidates", () => {
  test("includes date-prefixed Daily Project folders and sorts by newest date", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(
      brainRoot,
      "Daily Projects/2025-03-26-phe-survey/01 survey.md"
    )
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-04/02 plan.md")
    await writeBrainFile(brainRoot, "Daily Projects/not-a-date/01 ignored.md")
    await writeBrainFile(brainRoot, "Daily Projects/.hidden/01 ignored.md")
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-04/notes.txt")

    const result = await getBrainCollectionCandidates(
      brainRoot,
      "dailyProjects"
    )

    expect(result.candidates.map((candidate) => candidate.relativePath)).toEqual([
      "Daily Projects/2026-07-04/02 plan.md",
      "Daily Projects/2025-03-26-phe-survey/01 survey.md",
    ])
    expect(result.candidates[1].description).toBe("2025-03-26-phe-survey")
  })

  test("sorts Weekly Notes by week date descending and applies limits", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(brainRoot, "Weekly Notes/Week of 2026-06-28.md")
    await writeBrainFile(brainRoot, "Weekly Notes/Week of 2026-07-05.md")
    await writeBrainFile(brainRoot, "Weekly Notes/random.md")

    const result = await getBrainCollectionCandidates(brainRoot, "weeklyNotes", {
      limit: 1,
    })

    expect(result.candidates.map((candidate) => candidate.relativePath)).toEqual([
      "Weekly Notes/Week of 2026-07-05.md",
    ])
  })

  test("sorts Meeting Notes by meeting date before person and path", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(brainRoot, "Meeting Notes/alice/2026-07-03/02.md")
    await writeBrainFile(brainRoot, "Meeting Notes/bob/2026-07-04/01.md")
    await writeBrainFile(brainRoot, "Meeting Notes/alice/2026-07-04/01.md")
    await writeBrainFile(brainRoot, "Meeting Notes/.hidden/2026-07-05/01.md")
    await writeBrainFile(brainRoot, "Meeting Notes/bob/not-a-date/01.md")

    const result = await getBrainCollectionCandidates(brainRoot, "meetingNotes")

    expect(result.candidates.map((candidate) => candidate.relativePath)).toEqual([
      "Meeting Notes/alice/2026-07-04/01.md",
      "Meeting Notes/bob/2026-07-04/01.md",
      "Meeting Notes/alice/2026-07-03/02.md",
    ])
    expect(result.candidates[0].description).toBe("alice · 2026-07-04")
  })

  test("sorts Bookmarks by date folder descending and filters non-markdown files", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(brainRoot, "Bookmarks/2026-07-03/01 old.md")
    await writeBrainFile(brainRoot, "Bookmarks/2026-07-04/01 new.md")
    await writeBrainFile(brainRoot, "Bookmarks/2026-07-04/readme.txt")

    const result = await getBrainCollectionCandidates(brainRoot, "bookmarks")

    expect(result.candidates.map((candidate) => candidate.relativePath)).toEqual([
      "Bookmarks/2026-07-04/01 new.md",
      "Bookmarks/2026-07-03/01 old.md",
    ])
  })

  test("sorts Project Notes by depth and path without relying on mtime", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(brainRoot, "Projects/zeta/nested/deep.md")
    await writeBrainFile(brainRoot, "Projects/alpha/references.md")
    await writeBrainFile(brainRoot, "Projects/alpha/nested/context.md")
    await writeBrainFile(brainRoot, "Projects/.hidden/secret.md")
    await writeBrainFile(brainRoot, "Projects/alpha/note.txt")

    const result = await getBrainCollectionCandidates(brainRoot, "projectNotes")

    expect(result.candidates.map((candidate) => candidate.relativePath)).toEqual([
      "Projects/alpha/references.md",
      "Projects/alpha/nested/context.md",
      "Projects/zeta/nested/deep.md",
    ])
  })

  test("keeps shallow files from later projects reachable before nested early files consume the cap", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(brainRoot, "Projects/alpha/nested/01.md")
    await writeBrainFile(brainRoot, "Projects/alpha/nested/02.md")
    await writeBrainFile(brainRoot, "Projects/zeta/PROJECT.md")

    const result = await getBrainCollectionCandidates(brainRoot, "projectNotes", {
      limit: 10,
      maxProjectFiles: 2,
    })

    expect(result.candidates.map((candidate) => candidate.relativePath)).toEqual([
      "Projects/zeta/PROJECT.md",
      "Projects/alpha/nested/01.md",
    ])
  })

  test("does not use the smaller date-collection default limit for Project Notes", async () => {
    const brainRoot = await createTempBrain()
    for (let index = 0; index < 55; index += 1) {
      await writeBrainFile(
        brainRoot,
        `Projects/project-${String(index).padStart(2, "0")}/note.md`
      )
    }

    const result = await getBrainCollectionCandidates(brainRoot, "projectNotes")

    expect(result.candidates).toHaveLength(55)
    expect(result.candidates.at(-1)?.relativePath).toBe(
      "Projects/project-54/note.md"
    )
  })

  test("returns empty-state messages that explain the searched path", async () => {
    const brainRoot = await createTempBrain()

    expect(getBrainCollectionEmptyMessage(brainRoot, "dailyProjects")).toContain(
      path.join(brainRoot, "Daily Projects")
    )
    expect(getBrainCollectionEmptyMessage(brainRoot, "dailyProjects")).toContain(
      "date-prefixed"
    )

    const result = await getBrainCollectionCandidates(
      brainRoot,
      "dailyProjects"
    )
    expect(result.emptyMessage).toBe(
      getBrainCollectionEmptyMessage(brainRoot, "dailyProjects")
    )
  })
})
