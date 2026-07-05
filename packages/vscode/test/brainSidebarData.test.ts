import { afterEach, describe, expect, test } from "bun:test"
import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

import {
  getActiveContextFile,
  getDailyProjectFiles,
  getRecentSidebarFiles,
  getSidebarDayItemId,
  getSidebarSectionItemId,
  getWeeklyScheduleItems,
} from "../src/sidebar/brainSidebarData.js"

let tempRoots: string[] = []

async function createTempBrain(): Promise<string> {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "brain-sidebar-test-"))
  tempRoots.push(tempRoot)
  return tempRoot
}

async function writeBrainFile(
  brainRoot: string,
  relativePath: string,
  content = "# Test\n"
): Promise<string> {
  const absolutePath = path.join(brainRoot, relativePath)
  await fs.mkdir(path.dirname(absolutePath), { recursive: true })
  await fs.writeFile(absolutePath, content)
  return absolutePath
}

afterEach(async () => {
  await Promise.all(
    tempRoots.map((tempRoot) =>
      fs.rm(tempRoot, { recursive: true, force: true })
    )
  )
  tempRoots = []
})

describe("Brain sidebar data helpers", () => {
  test("uses stable TreeItem IDs for collapsible sidebar rows", () => {
    expect(getSidebarSectionItemId("today")).toBe("section:today")
    expect(getSidebarSectionItemId("week")).toBe("section:week")
    expect(getSidebarSectionItemId("recent")).toBe("section:recent")
    expect(getSidebarSectionItemId("active")).toBe("section:active")
    expect(getSidebarDayItemId("2026-07-05")).toBe("day:2026-07-05")
  })

  test("sorts today's Daily Projects newest numbered file first", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-05/01 first.md")
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-05/03 third.md")
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-05/02 second.md")
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-05/.hidden.md")
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-05/not-markdown.txt")

    expect(
      (await getDailyProjectFiles(brainRoot, "2026-07-05")).map(
        (file) => file.relativePath
      )
    ).toEqual([
      "Daily Projects/2026-07-05/03 third.md",
      "Daily Projects/2026-07-05/02 second.md",
      "Daily Projects/2026-07-05/01 first.md",
    ])
  })

  test("parses schedule items for one date from the weekly note", async () => {
    const brainRoot = await createTempBrain()
    await writeBrainFile(
      brainRoot,
      "Weekly Notes/Week of 2026-07-05.md",
      [
        "# Week",
        "",
        "## Schedule",
        "- Sunday (2026-07-05)",
        "\t- [ ] 0900 [[Meeting Notes/tgthorley/2026-07-05/01|1:1]]",
        "\t- [ ] 1100 Snippets",
        "- Monday (2026-07-06)",
        "\t- [ ] 1000 Other",
        "",
        "## TODO",
      ].join("\n")
    )

    expect(
      await getWeeklyScheduleItems(
        brainRoot,
        new Date(2026, 6, 5),
        "2026-07-05"
      )
    ).toEqual([
      {
        time: "0900",
        description: "tgthorley",
        filePath: path.join(
          brainRoot,
          "Meeting Notes",
          "tgthorley",
          "2026-07-05",
          "01.md"
        ),
      },
      { time: "1100", description: "Snippets" },
    ])
  })

  test("keeps active context inside the Brain and limited to Markdown files", async () => {
    const brainRoot = await createTempBrain()
    const brainFile = await writeBrainFile(
      brainRoot,
      "Daily Projects/2026-07-05/01 active.md"
    )
    const outsideRoot = await fs.mkdtemp(path.join(os.tmpdir(), "outside-brain-"))
    tempRoots.push(outsideRoot)
    const outsideFile = path.join(outsideRoot, "note.md")
    await fs.writeFile(outsideFile, "# Outside\n")

    expect(getActiveContextFile(brainRoot, brainFile)?.relativePath).toBe(
      "Daily Projects/2026-07-05/01 active.md"
    )
    expect(getActiveContextFile(brainRoot, outsideFile)).toBeNull()
    expect(getActiveContextFile(brainRoot, path.join(brainRoot, "note.txt"))).toBeNull()
  })

  test("uses bounded recent sources and respects the sidebar limit", async () => {
    const brainRoot = await createTempBrain()
    const now = new Date(2026, 6, 5, 12)
    await writeBrainFile(brainRoot, "Weekly Notes/Week of 2026-07-05.md")
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-05/01 first.md")
    await writeBrainFile(brainRoot, "Daily Projects/2026-07-05/02 second.md")

    expect(
      (await getRecentSidebarFiles(brainRoot, { limit: 2, now })).map(
        (file) => file.relativePath
      )
    ).toHaveLength(2)
  })
})
