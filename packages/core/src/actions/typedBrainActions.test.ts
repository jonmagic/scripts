/// <reference types="bun-types" />

import { describe, expect, test } from "bun:test"
import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

import {
  appendProjectReference,
  appendWeeklyNoteTodo,
  createPathWikilinkForFile,
  createUidWikilinkForFile,
  extractMarkdownLevelTwoHeadings,
  parseLocalDateYYYYMMDD,
} from "./typedBrainActions.js"

async function createBrainRoot(): Promise<string> {
  return fs.mkdtemp(path.join(os.tmpdir(), "brain-actions-"))
}

describe("typed Brain actions", () => {
  test("creates path and UID wikilinks for Markdown files inside Brain", async () => {
    const brainRoot = await createBrainRoot()
    const filePath = path.join(
      brainRoot,
      "Daily Projects",
      "2026-07-04",
      "01 typed actions.md"
    )
    await fs.mkdir(path.dirname(filePath), { recursive: true })
    await fs.writeFile(
      filePath,
      "---\nuid: 3abc123def456\ntype: daily.project\n---\n\n# Typed actions\n"
    )

    const pathLink = await createPathWikilinkForFile({ brainRoot, filePath })
    const uidLink = await createUidWikilinkForFile({ brainRoot, filePath })

    expect(pathLink.wikilink).toBe(
      "[[Daily Projects/2026-07-04/01 typed actions]]"
    )
    expect(uidLink.wikilink).toBe(
      "[[uid:3abc123def456|Daily Projects/2026-07-04/01 typed actions]]"
    )
  })

  test("rejects UID wikilinks when frontmatter has no uid", async () => {
    const brainRoot = await createBrainRoot()
    const filePath = path.join(brainRoot, "Projects", "alpha", "note.md")
    await fs.mkdir(path.dirname(filePath), { recursive: true })
    await fs.writeFile(filePath, "# No UID\n")

    await expect(
      createUidWikilinkForFile({ brainRoot, filePath })
    ).rejects.toThrow("does not have a uid")
  })

  test("rejects sibling paths outside the configured Brain root", async () => {
    const parent = await fs.mkdtemp(path.join(os.tmpdir(), "brain-boundary-"))
    const brainRoot = path.join(parent, "Brain")
    const siblingRoot = path.join(parent, "Brain-evil")
    const siblingFile = path.join(siblingRoot, "note.md")
    await fs.mkdir(brainRoot, { recursive: true })
    await fs.mkdir(siblingRoot, { recursive: true })
    await fs.writeFile(siblingFile, "# Outside\n")

    await expect(
      createPathWikilinkForFile({ brainRoot, filePath: siblingFile })
    ).rejects.toThrow("outside the configured Brain folder")
  })

  test("rejects symlinked files that resolve outside the configured Brain root", async () => {
    const parent = await fs.mkdtemp(path.join(os.tmpdir(), "brain-symlink-"))
    const brainRoot = path.join(parent, "Brain")
    const outsideRoot = path.join(parent, "outside")
    const outsideFile = path.join(outsideRoot, "outside.md")
    const symlinkFile = path.join(brainRoot, "Projects", "outside.md")
    await fs.mkdir(path.dirname(symlinkFile), { recursive: true })
    await fs.mkdir(outsideRoot, { recursive: true })
    await fs.writeFile(outsideFile, "# Outside\n")
    await fs.symlink(outsideFile, symlinkFile)

    await expect(
      createPathWikilinkForFile({ brainRoot, filePath: symlinkFile })
    ).rejects.toThrow("outside the configured Brain folder")
  })

  test("parses local YYYY-MM-DD dates strictly", () => {
    const date = parseLocalDateYYYYMMDD("2026-07-04")

    expect(date.getFullYear()).toBe(2026)
    expect(date.getMonth()).toBe(6)
    expect(date.getDate()).toBe(4)
    expect(() => parseLocalDateYYYYMMDD("2026-7-4")).toThrow("YYYY-MM-DD")
    expect(() => parseLocalDateYYYYMMDD("2026-02-31")).toThrow("valid date")
  })

  test("appends and deduplicates TODOs in an existing weekly note", async () => {
    const brainRoot = await createBrainRoot()
    const weeklyPath = path.join(
      brainRoot,
      "Weekly Notes",
      "Week of 2026-07-05.md"
    )
    await fs.mkdir(path.dirname(weeklyPath), { recursive: true })
    await fs.writeFile(
      weeklyPath,
      "# Week of 2026-07-05\n\n## TODO\n- [ ] Existing task\n\n## Schedule\n"
    )

    const first = await appendWeeklyNoteTodo({
      brainRoot,
      date: parseLocalDateYYYYMMDD("2026-07-05"),
      text: "Follow up on typed actions",
    })
    const second = await appendWeeklyNoteTodo({
      brainRoot,
      date: parseLocalDateYYYYMMDD("2026-07-05"),
      text: "Follow up on typed actions",
    })

    const content = await fs.readFile(weeklyPath, "utf8")
    expect(first.updated).toBe(true)
    expect(second.alreadyPresent).toBe(true)
    expect(
      content.match(/- \[ \] Follow up on typed actions/g)?.length
    ).toBe(1)
    expect(content.indexOf("- [ ] Follow up on typed actions")).toBeLessThan(
      content.indexOf("## Schedule")
    )
  })

  test("fails explicitly when the weekly note is missing", async () => {
    const brainRoot = await createBrainRoot()

    await expect(
      appendWeeklyNoteTodo({
        brainRoot,
        date: parseLocalDateYYYYMMDD("2026-07-05"),
        text: "Missing note task",
      })
    ).rejects.toThrow("Weekly note not found")
  })

  test("extracts level-two headings and appends project references under a selected heading", async () => {
    const brainRoot = await createBrainRoot()
    const referencesPath = path.join(brainRoot, "Projects", "alpha", "references.md")
    await fs.mkdir(path.dirname(referencesPath), { recursive: true })
    await fs.writeFile(
      referencesPath,
      "# Alpha references\n\n## Brain notes\n- [[Daily Projects/2026-07-04/01 existing]]\n\n## External references\n"
    )

    const content = await fs.readFile(referencesPath, "utf8")
    expect(extractMarkdownLevelTwoHeadings(content)).toEqual([
      "Brain notes",
      "External references",
    ])

    const first = await appendProjectReference({
      brainRoot,
      referencesPath,
      heading: "Brain notes",
      reference: "[[Daily Projects/2026-07-04/02 typed actions]]",
    })
    const second = await appendProjectReference({
      brainRoot,
      referencesPath,
      heading: "Brain notes",
      reference: "[[Daily Projects/2026-07-04/02 typed actions]]",
    })

    const updated = await fs.readFile(referencesPath, "utf8")
    expect(first.updated).toBe(true)
    expect(second.alreadyPresent).toBe(true)
    expect(
      updated.match(/\[\[Daily Projects\/2026-07-04\/02 typed actions\]\]/g)
        ?.length
    ).toBe(1)
    expect(updated.indexOf("[[Daily Projects/2026-07-04/02 typed actions]]")).toBeLessThan(
      updated.indexOf("## External references")
    )
  })

  test("fails when a project references heading is absent", async () => {
    const brainRoot = await createBrainRoot()
    const referencesPath = path.join(brainRoot, "Projects", "alpha", "references.md")
    await fs.mkdir(path.dirname(referencesPath), { recursive: true })
    await fs.writeFile(referencesPath, "# Alpha references\n\n## Brain notes\n")

    await expect(
      appendProjectReference({
        brainRoot,
        referencesPath,
        heading: "External references",
        reference: "https://example.com",
      })
    ).rejects.toThrow('Heading "External references" not found')
  })
})
