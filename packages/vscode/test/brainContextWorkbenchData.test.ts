import { describe, expect, test } from "bun:test"
import * as path from "node:path"

import {
  buildBrainContextWorkbenchData,
  getActiveBrainMarkdownFile,
  getProjectReferenceCandidates,
} from "../src/context/brainContextWorkbenchData.js"

describe("Brain context workbench data", () => {
  test("does no work for non-file, non-Markdown, or missing active editors", () => {
    expect(getActiveBrainMarkdownFile("/Brain", undefined).state).toBe(
      "noActiveMarkdown"
    )
    expect(
      getActiveBrainMarkdownFile("/Brain", {
        filePath: "/Brain/note.md",
        languageId: "markdown",
        scheme: "vscode-notebook",
      }).state
    ).toBe("noActiveMarkdown")
    expect(
      getActiveBrainMarkdownFile("/Brain", {
        filePath: "/Brain/note.txt",
        languageId: "plaintext",
        scheme: "file",
      }).state
    ).toBe("noActiveMarkdown")
  })

  test("reports active Markdown files outside the Brain root without context", () => {
    const result = getActiveBrainMarkdownFile("/Brain", {
      filePath: "/outside/note.md",
      languageId: "markdown",
      scheme: "file",
    })

    expect(result.state).toBe("outsideBrain")
    expect(result.message).toBe("Active file is outside the configured Brain folder")
    expect(result.sections).toEqual([])
  })

  test("derives capped context from frontmatter links and active-buffer wikilinks", () => {
    const activeFile = {
      absolutePath: path.join(
        "/Brain",
        "Daily Projects/2026-07-04/07 plan.md"
      ),
      relativePath: "Daily Projects/2026-07-04/07 plan.md",
    }
    const content = `---
uid: 3mptvhhdstwsc
links:
  parent:
    - "[[uid:3mptpqmby3ea7|Daily Projects/2026-07-04/02 scripts brain extension ideas and requirements]]"
  source:
    - "https://example.com/source"
  related:
    - "[[uid:3mptr4wb275dl|Daily Projects/2026-07-04/03 scripts brain quick open execution plan]]"
---

See [[Projects/scripts/references|scripts references]] and [[uid:abc123|UID Link]].
`

    const result = buildBrainContextWorkbenchData({
      activeFile,
      backlinkIndexReady: false,
      content,
    })

    expect(result.sections.map((section) => section.id)).toEqual([
      "frontmatter",
      "sources",
      "outgoing",
      "backlinks",
    ])
    expect(result.sections[0]?.references).toMatchObject([
      {
        description: "parent",
        kind: "reference",
        label:
          "Daily Projects/2026-07-04/02 scripts brain extension ideas and requirements",
        reference: "uid:3mptpqmby3ea7",
      },
      {
        description: "related",
        kind: "reference",
        label:
          "Daily Projects/2026-07-04/03 scripts brain quick open execution plan",
        reference: "uid:3mptr4wb275dl",
      },
    ])
    expect(result.sections[1]?.references).toEqual([
      {
        description: "source",
        kind: "url",
        label: "https://example.com/source",
        url: "https://example.com/source",
      },
    ])
    expect(result.sections[2]?.references.map((reference) => reference.reference)).toEqual([
      "Projects/scripts/references",
      "uid:abc123",
    ])
    expect(result.sections[3]?.emptyMessage).toContain(
      "existing Brain workspace cache"
    )
  })

  test("uses existing backlinks and project references when supplied", () => {
    const result = buildBrainContextWorkbenchData({
      activeFile: {
        absolutePath: "/Brain/Projects/scripts/note.md",
        relativePath: "Projects/scripts/note.md",
      },
      backlinkIndexReady: true,
      backlinks: [
        "Daily Projects/2026-07-04/07 plan",
        "Daily Projects/2026-07-04/07 plan",
      ],
      content: "# Project note\n",
      existingProjectReferencePaths: [
        "Projects/scripts/references.md",
        "Projects/scripts/executive summary.md",
      ],
    })

    expect(result.sections.map((section) => section.id)).toEqual([
      "backlinks",
      "project",
    ])
    expect(result.sections[0]?.references).toEqual([
      {
        description: "backlink",
        kind: "file",
        label: "07 plan",
        relativePath: "Daily Projects/2026-07-04/07 plan.md",
      },
    ])
    expect(result.sections[1]?.references.map((reference) => reference.relativePath)).toEqual([
      "Projects/scripts/references.md",
      "Projects/scripts/executive summary.md",
    ])
  })

  test("keeps project reference candidates scoped to the active project slug", () => {
    expect(getProjectReferenceCandidates("Projects/scripts/note.md")).toEqual([
      "Projects/scripts/references.md",
      "Projects/scripts/executive summary.md",
    ])
    expect(getProjectReferenceCandidates("Daily Projects/2026-07-04/07.md")).toEqual(
      []
    )
  })
})
