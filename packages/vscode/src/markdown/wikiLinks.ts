import * as path from "node:path"
import type { Uri } from "vscode"
import {
  parseWikilink,
  pathToDisplayPath,
  resolveWikilink,
} from "@jonmagic/scripts-core"
import { getWorkspaceCache } from "../cache/workspaceCache"
import { getRelativeBrainPath } from "../config/brainPath"

type MarkdownRenderEnv = {
  currentDocument?: Uri
}

type MarkdownToken = {
  attrSet(name: string, value: string): void
  content: string
  meta?: BrainWikilinkMeta
}

type MarkdownInlineState = {
  env: unknown
  pos: number
  posMax: number
  push(type: string, tag: string, nesting: number): MarkdownToken
  src: string
}

type MarkdownRendererRule = (
  tokens: MarkdownToken[],
  idx: number,
  options: unknown,
  env: MarkdownRenderEnv,
  self: unknown
) => string

export type MarkdownItLike = {
  inline: {
    ruler: {
      before(
        beforeName: string,
        ruleName: string,
        rule: (state: MarkdownInlineState, silent: boolean) => boolean
      ): void
    }
  }
  renderer: {
    rules: Record<string, MarkdownRendererRule | undefined>
  }
}

type BrainWikilinkMeta = {
  resolvedPath: string
  label: string
  title: string
}

function encodeHrefPath(relativePath: string): string {
  return relativePath
    .split("/")
    .map((segment) => {
      if (segment === "." || segment === "..") {
        return segment
      }

      return encodeURIComponent(segment)
    })
    .join("/")
}

function buildPreviewHref(
  targetRelativePath: string,
  currentDocumentPath?: string
): string {
  const normalizedTarget = targetRelativePath.replace(/\\/g, "/")

  if (!currentDocumentPath) {
    return encodeHrefPath(normalizedTarget)
  }

  const currentRelativePath = getRelativeBrainPath(currentDocumentPath)
  if (!currentRelativePath) {
    return encodeHrefPath(normalizedTarget)
  }

  const sourceDir = path.posix.dirname(currentRelativePath)
  let relativeHref =
    path.posix.relative(sourceDir, normalizedTarget) ||
    path.posix.basename(normalizedTarget)

  if (!relativeHref.startsWith(".") && !relativeHref.startsWith("/")) {
    relativeHref = `./${relativeHref}`
  }

  return encodeHrefPath(relativeHref)
}

function resolvePreviewLink(target: string, label: string | undefined): BrainWikilinkMeta | null {
  const cache = getWorkspaceCache()
  const resolvedPath = resolveWikilink(
    target,
    cache.getUidIndex(),
    cache.getMarkdownFiles()
  )

  if (!resolvedPath) {
    return null
  }

  return {
    resolvedPath,
    label: label ?? (target.startsWith("uid:") ? pathToDisplayPath(resolvedPath) : target),
    title: pathToDisplayPath(resolvedPath),
  }
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function renderBrainWikilink(
  tokens: MarkdownToken[],
  idx: number,
  _options: unknown,
  env: MarkdownRenderEnv
): string {
  const token = tokens[idx]
  const meta = token?.meta

  if (!meta) {
    return escapeHtml(token?.content ?? "")
  }

  const href = buildPreviewHref(meta.resolvedPath, env.currentDocument?.fsPath)
  const escapedHref = escapeHtml(href)
  const escapedTitle = escapeHtml(meta.title)
  const escapedLabel = escapeHtml(meta.label)

  return `<a href="${escapedHref}" data-href="${escapedHref}" title="${escapedTitle}">${escapedLabel}</a>`
}

export function extendBrainMarkdownIt(md: MarkdownItLike): MarkdownItLike {
  md.renderer.rules.brain_wikilink = renderBrainWikilink

  md.inline.ruler.before(
    "link",
    "brain_wikilink",
    (state: MarkdownInlineState, silent: boolean): boolean => {
      const start = state.pos
      if (
        state.src.charCodeAt(start) !== 0x5b ||
        state.src.charCodeAt(start + 1) !== 0x5b
      ) {
        return false
      }

      const end = state.src.indexOf("]]", start + 2)
      if (end === -1 || end >= state.posMax) {
        return false
      }

      const rawWikilink = state.src.slice(start, end + 2)
      const parsed = parseWikilink(rawWikilink)

      if (silent) {
        return true
      }

      const resolved = resolvePreviewLink(parsed.target, parsed.label)

      if (!resolved) {
        const unresolvedText = state.push("text", "", 0)
        unresolvedText.content = rawWikilink
        state.pos = end + 2
        return true
      }

      const wikilinkToken = state.push("brain_wikilink", "", 0)
      wikilinkToken.meta = resolved
      wikilinkToken.content = resolved.label
      state.pos = end + 2
      return true
    }
  )

  return md
}
