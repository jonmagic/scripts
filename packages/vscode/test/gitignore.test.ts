import { afterEach, describe, expect, test } from "bun:test"
import * as fs from "node:fs/promises"
import * as os from "node:os"
import * as path from "node:path"

import { GitignoreMatcher } from "../src/cache/gitignore.js"

let tempRoots: string[] = []

async function createTempRoot(): Promise<string> {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gitignore-test-"))
  tempRoots.push(tempRoot)
  return tempRoot
}

afterEach(async () => {
  await Promise.all(
    tempRoots.map((tempRoot) =>
      fs.rm(tempRoot, { recursive: true, force: true })
    )
  )
  tempRoots = []
})

describe("GitignoreMatcher", () => {
  test("ignores files under directory-only rules", async () => {
    const root = await createTempRoot()
    await fs.writeFile(path.join(root, ".gitignore"), ".corpus-loop/\n")

    const matcher = new GitignoreMatcher(root)

    expect(
      await matcher.isIgnored(path.join(root, ".corpus-loop"), {
        isDirectory: true,
      })
    ).toBe(true)
    expect(await matcher.isIgnored(path.join(root, ".corpus-loop/a.md"))).toBe(
      true
    )
    expect(await matcher.isIgnored(path.join(root, "notes/a.md"))).toBe(false)
  })

  test("matches basename rules at any depth", async () => {
    const root = await createTempRoot()
    await fs.writeFile(path.join(root, ".gitignore"), "*.tmp\n")

    const matcher = new GitignoreMatcher(root)

    expect(await matcher.isIgnored(path.join(root, "notes/cache.tmp"))).toBe(
      true
    )
    expect(await matcher.isIgnored(path.join(root, "notes/cache.md"))).toBe(
      false
    )
  })

  test("keeps anchored rules relative to the gitignore directory", async () => {
    const root = await createTempRoot()
    await fs.writeFile(path.join(root, ".gitignore"), "/drafts\n")

    const matcher = new GitignoreMatcher(root)

    expect(
      await matcher.isIgnored(path.join(root, "drafts"), { isDirectory: true })
    ).toBe(true)
    expect(
      await matcher.isIgnored(path.join(root, "nested/drafts"), {
        isDirectory: true,
      })
    ).toBe(false)
  })

  test("allows later negated rules to re-include files", async () => {
    const root = await createTempRoot()
    await fs.writeFile(path.join(root, ".gitignore"), "*.md\n!keep.md\n")

    const matcher = new GitignoreMatcher(root)

    expect(await matcher.isIgnored(path.join(root, "drop.md"))).toBe(true)
    expect(await matcher.isIgnored(path.join(root, "keep.md"))).toBe(false)
  })

  test("loads nested gitignore files", async () => {
    const root = await createTempRoot()
    const nested = path.join(root, "nested")
    await fs.mkdir(nested)
    await fs.writeFile(path.join(nested, ".gitignore"), "local.md\n")

    const matcher = new GitignoreMatcher(root)

    expect(await matcher.isIgnored(path.join(nested, "local.md"))).toBe(true)
    expect(await matcher.isIgnored(path.join(root, "local.md"))).toBe(false)
  })
})
