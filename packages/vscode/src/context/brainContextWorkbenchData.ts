import * as path from "node:path"

import {
  extractWikilinks,
  parseFrontmatter,
  parseWikilink,
  UID_PREFIX,
} from "@jonmagic/scripts-core"

export const CONTEXT_WORKBENCH_REFERENCE_LIMIT = 8

export type BrainContextWorkbenchState =
  | "noActiveMarkdown"
  | "outsideBrain"
  | "ready"

export type BrainContextSectionId =
  | "frontmatter"
  | "sources"
  | "outgoing"
  | "backlinks"
  | "project"

export type BrainContextReferenceKind = "file" | "reference" | "url"

export interface ActiveEditorContext {
  filePath?: string
  languageId?: string
  scheme?: string
}

export interface ActiveBrainMarkdownFile {
  absolutePath: string
  relativePath: string
}

export interface BrainContextReference {
  description: string
  kind: BrainContextReferenceKind
  label: string
  reference?: string
  relativePath?: string
  url?: string
}

export interface BrainContextSection {
  description: string
  emptyMessage?: string
  id: BrainContextSectionId
  label: string
  references: BrainContextReference[]
}

export interface BrainContextWorkbenchData {
  activeFile?: ActiveBrainMarkdownFile
  description: string
  message: string
  sections: BrainContextSection[]
  state: BrainContextWorkbenchState
}

export interface BuildBrainContextWorkbenchDataOptions {
  activeFile: ActiveBrainMarkdownFile
  backlinkIndexReady?: boolean
  backlinks?: string[]
  content: string
  existingProjectReferencePaths?: string[]
}

function normalizePath(filePath: string): string {
  return filePath.replace(/\\/g, "/")
}

function getRelativePath(
  brainRoot: string,
  absolutePath: string
): string | null {
  const relativePath = path.relative(brainRoot, absolutePath)

  if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
    return null
  }

  return normalizePath(relativePath)
}

function stripMarkdownExtension(relativePath: string): string {
  return relativePath.endsWith(".md") ? relativePath.slice(0, -3) : relativePath
}

function labelFromPath(relativePath: string): string {
  return path.basename(relativePath, ".md")
}

function labelFromTarget(target: string): string {
  if (target.startsWith(UID_PREFIX)) {
    return target
  }

  return stripMarkdownExtension(target).split("/").at(-1) ?? target
}

function isUrl(value: string): boolean {
  return /^https?:\/\//i.test(value)
}

function dedupeReferences(
  references: BrainContextReference[]
): BrainContextReference[] {
  const seen = new Set<string>()
  const deduped: BrainContextReference[] = []

  for (const reference of references) {
    const key =
      reference.url ??
      reference.relativePath ??
      reference.reference ??
      `${reference.kind}:${reference.label}:${reference.description}`

    if (seen.has(key)) {
      continue
    }

    seen.add(key)
    deduped.push(reference)
  }

  return deduped.slice(0, CONTEXT_WORKBENCH_REFERENCE_LIMIT)
}

function referenceFromValue(
  value: string,
  description: string
): BrainContextReference | null {
  const trimmed = value.trim()
  if (!trimmed) {
    return null
  }

  if (isUrl(trimmed)) {
    return {
      description,
      kind: "url",
      label: trimmed,
      url: trimmed,
    }
  }

  const parsed =
    trimmed.startsWith("[[") && trimmed.endsWith("]]")
      ? parseWikilink(trimmed)
      : null
  const target = parsed?.target ?? trimmed
  const label = parsed?.label ?? labelFromTarget(target)

  if (isUrl(target)) {
    return {
      description,
      kind: "url",
      label,
      url: target,
    }
  }

  return {
    description,
    kind: "reference",
    label,
    reference: target,
  }
}

function fileReference(
  relativePath: string,
  description: string
): BrainContextReference {
  return {
    description,
    kind: "file",
    label: labelFromPath(relativePath),
    relativePath,
  }
}

function buildSection(
  id: BrainContextSectionId,
  label: string,
  description: string,
  references: BrainContextReference[],
  emptyMessage?: string
): BrainContextSection | null {
  const deduped = dedupeReferences(references)

  if (deduped.length === 0 && !emptyMessage) {
    return null
  }

  return {
    description,
    id,
    label,
    references: deduped,
    ...(emptyMessage === undefined ? {} : { emptyMessage }),
  }
}

function frontmatterReferences(
  values: string[] | undefined,
  description: string
): BrainContextReference[] {
  return (values ?? [])
    .map((value) => referenceFromValue(value, description))
    .filter((reference): reference is BrainContextReference => reference !== null)
}

export function getActiveBrainMarkdownFile(
  brainRoot: string,
  editor: ActiveEditorContext | undefined
): BrainContextWorkbenchData {
  if (
    !editor?.filePath ||
    editor.scheme !== "file" ||
    editor.languageId !== "markdown" ||
    !editor.filePath.endsWith(".md")
  ) {
    return {
      description: "open a Brain Markdown file to populate this view",
      message: "No active Brain Markdown file",
      sections: [],
      state: "noActiveMarkdown",
    }
  }

  const relativePath = getRelativePath(brainRoot, editor.filePath)
  if (!relativePath) {
    return {
      description: "no Brain context loaded",
      message: "Active file is outside the configured Brain folder",
      sections: [],
      state: "outsideBrain",
    }
  }

  return {
    activeFile: {
      absolutePath: editor.filePath,
      relativePath,
    },
    description: relativePath,
    message: "Active Brain context",
    sections: [],
    state: "ready",
  }
}

export function getProjectReferenceCandidates(relativePath: string): string[] {
  const parts = relativePath.split("/")
  if (parts[0] !== "Projects" || !parts[1]) {
    return []
  }

  const projectRoot = `Projects/${parts[1]}`
  return [
    `${projectRoot}/references.md`,
    `${projectRoot}/executive summary.md`,
  ]
}

export function buildBrainContextWorkbenchData(
  options: BuildBrainContextWorkbenchDataOptions
): BrainContextWorkbenchData {
  const { frontmatter, body } = parseFrontmatter(options.content)
  const links = frontmatter?.links
  const sections: BrainContextSection[] = []
  const frontmatterSection = buildSection(
    "frontmatter",
    "Linked Context",
    "frontmatter parent and related links",
    [
      ...frontmatterReferences(links?.parent, "parent"),
      ...frontmatterReferences(links?.related, "related"),
    ]
  )
  const sourceSection = buildSection(
    "sources",
    "Source Trails",
    "frontmatter source links",
    frontmatterReferences(links?.source, "source")
  )
  const outgoingSection = buildSection(
    "outgoing",
    "Outgoing Wikilinks",
    "wikilinks in the active file",
    extractWikilinks(body).map((link) => ({
      description: "wikilink",
      kind: "reference",
      label: link.label ?? labelFromTarget(link.target),
      reference: link.target,
    }))
  )
  const backlinkSection = buildSection(
    "backlinks",
    "Backlinks",
    options.backlinkIndexReady
      ? "existing workspace backlink index"
      : "existing workspace backlink index not loaded",
    (options.backlinks ?? []).map((backlink) =>
      fileReference(
        backlink.endsWith(".md") ? backlink : `${backlink}.md`,
        "backlink"
      )
    ),
    options.backlinkIndexReady
      ? undefined
      : "Backlinks are available after the existing Brain workspace cache loads"
  )
  const projectSection = buildSection(
    "project",
    "Project References",
    "current project files",
    (options.existingProjectReferencePaths ?? []).map((relativePath) =>
      fileReference(relativePath, "project")
    )
  )

  for (const section of [
    frontmatterSection,
    sourceSection,
    outgoingSection,
    backlinkSection,
    projectSection,
  ]) {
    if (section) {
      sections.push(section)
    }
  }

  return {
    activeFile: options.activeFile,
    description: options.activeFile.relativePath,
    message: "Active Brain context",
    sections,
    state: "ready",
  }
}
