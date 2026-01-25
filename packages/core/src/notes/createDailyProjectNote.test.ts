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
      date
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
      date
    })
    expect(r2.number).toBe(2)
  })
})
