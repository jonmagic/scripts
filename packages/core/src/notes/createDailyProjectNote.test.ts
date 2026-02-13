/// <reference types="bun-types" />

import { describe, expect, test } from "bun:test"
import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

import { createDailyProjectNote } from "./createDailyProjectNote.js"

describe("createDailyProjectNote", () => {
  test("creates a numbered file under Daily Projects/YYYY-MM-DD", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 0, 19, 12, 0, 0)

    const r1 = await createDailyProjectNote({
      title: "refactor stale queue cleanup",
      brainRoot: tmp,
      date,
      session: false,
    })

    expect(r1.number).toBe(1)
    expect(r1.filePath).toEndWith(
      path.join(
        "Daily Projects",
        "2026-01-19",
        "01 refactor stale queue cleanup.md"
      )
    )

    const r2 = await createDailyProjectNote({
      title: "second thing",
      brainRoot: tmp,
      date,
      session: false,
    })
    expect(r2.number).toBe(2)
  })

  test("includes frontmatter with uid, type, created", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 0, 19, 12, 0, 0)

    const result = await createDailyProjectNote({
      title: "test frontmatter",
      brainRoot: tmp,
      date,
      session: false,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toStartWith("---\n")
    expect(content).toContain("uid: ")
    expect(content).toContain("type: daily.project")
    expect(content).toContain("created: 2026-01-19T00:00:00Z")
    expect(content).toContain("---\n\n# test frontmatter")
    // uid should be returned in result
    expect(result.uid).toBeTruthy()
    expect(result.uid.length).toBe(13)
  })

  test("includes session in frontmatter when explicitly provided", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 0, 19, 12, 0, 0)

    const result = await createDailyProjectNote({
      title: "test with session",
      brainRoot: tmp,
      date,
      session: "opencode -s ses_abc123",
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).toContain("session: opencode -s ses_abc123")
    expect(result.session).toBe("opencode -s ses_abc123")
  })

  test("omits session from frontmatter when set to false", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "brain-"))
    const date = new Date(2026, 0, 19, 12, 0, 0)

    const result = await createDailyProjectNote({
      title: "test no session",
      brainRoot: tmp,
      date,
      session: false,
    })

    const content = await fs.readFile(result.filePath, "utf8")
    expect(content).not.toContain("session:")
    expect(result.session).toBeUndefined()
  })
})
