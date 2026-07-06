import * as path from "node:path"
import * as fs from "node:fs/promises"
import * as vscode from "vscode"
import { pathToDisplayPath } from "@jonmagic/scripts-core"

import { getWorkspaceCache } from "../cache/workspaceCache"
import { getBrainPath } from "../config/brainPath"
import {
  buildBrainContextWorkbenchData,
  getActiveBrainMarkdownFile,
  getProjectReferenceCandidates,
  type BrainContextReference,
  type BrainContextSection,
  type BrainContextWorkbenchData,
  type ActiveEditorContext,
} from "./brainContextWorkbenchData"

type BrainContextWorkbenchItemType = "section" | "reference" | "empty" | "error"

interface ErrorWithCode extends Error {
  code?: string
}

interface BrainContextWorkbenchItemOptions {
  icon?: string
  itemType?: BrainContextWorkbenchItemType
  reference?: BrainContextReference
  section?: BrainContextSection
}

export class BrainContextWorkbenchItem extends vscode.TreeItem {
  readonly itemType: BrainContextWorkbenchItemType
  readonly reference: BrainContextReference | undefined
  readonly section: BrainContextSection | undefined

  constructor(
    label: string,
    collapsibleState: vscode.TreeItemCollapsibleState,
    options: BrainContextWorkbenchItemOptions = {}
  ) {
    super(label, collapsibleState)
    this.itemType = options.itemType ?? "section"
    this.reference = options.reference
    this.section = options.section

    if (options.icon) {
      this.iconPath = new vscode.ThemeIcon(options.icon)
    }
  }
}

function isErrorWithCode(error: unknown): error is ErrorWithCode {
  return error instanceof Error && "code" in error
}

function getActiveEditorContext(
  editor: vscode.TextEditor | undefined
): ActiveEditorContext | undefined {
  if (!editor) {
    return undefined
  }

  return {
    filePath: editor.document.uri.fsPath,
    languageId: editor.document.languageId,
    scheme: editor.document.uri.scheme,
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

async function pathExists(filePath: string): Promise<boolean> {
  try {
    const stat = await fs.stat(filePath)
    return stat.isFile()
  } catch (error) {
    if (isErrorWithCode(error) && error.code === "ENOENT") {
      return false
    }

    throw error
  }
}

export class BrainContextWorkbenchProvider
  implements vscode.TreeDataProvider<BrainContextWorkbenchItem>
{
  private refreshTimer: ReturnType<typeof setTimeout> | null = null
  private _onDidChangeTreeData: vscode.EventEmitter<
    BrainContextWorkbenchItem | undefined | null | void
  > = new vscode.EventEmitter<BrainContextWorkbenchItem | undefined | null | void>()
  readonly onDidChangeTreeData: vscode.Event<
    BrainContextWorkbenchItem | undefined | null | void
  > = this._onDidChangeTreeData.event

  private activeEditor = vscode.window.activeTextEditor
  private activeEditorVersion = 0

  setActiveEditor(editor: vscode.TextEditor | undefined): void {
    this.activeEditor = editor
    this.activeEditorVersion += 1
    this.refresh()
  }

  refresh(): void {
    this._onDidChangeTreeData.fire()
  }

  refreshSoon(delayMs = 200): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer)
    }

    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = null
      this.refresh()
    }, delayMs)
  }

  dispose(): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer)
      this.refreshTimer = null
    }
  }

  getTreeItem(element: BrainContextWorkbenchItem): vscode.TreeItem {
    return element
  }

  async getChildren(
    element?: BrainContextWorkbenchItem
  ): Promise<BrainContextWorkbenchItem[]> {
    try {
      if (element?.section) {
        return this.getSectionItems(element.section)
      }

      return await this.getRootItems()
    } catch (error) {
      return [this.createErrorItem(errorMessage(error))]
    }
  }

  private async getRootItems(): Promise<BrainContextWorkbenchItem[]> {
    const data = await this.getContextData()

    if (data.state !== "ready") {
      return [this.createEmptyItem(data.message, data.description)]
    }

    if (data.sections.length === 0) {
      return [
        this.createEmptyItem(
          "No related context found",
          "checked frontmatter and active-file wikilinks"
        ),
      ]
    }

    return data.sections.map((section) => this.createSectionItem(section))
  }

  private async getContextData(): Promise<BrainContextWorkbenchData> {
    while (true) {
      const brainRoot = getBrainPath()
      const editor = this.activeEditor
      const document = editor?.document
      const activeEditorVersion = this.activeEditorVersion
      const activeData = getActiveBrainMarkdownFile(
        brainRoot,
        getActiveEditorContext(editor)
      )

      if (activeData.state !== "ready" || !activeData.activeFile) {
        return activeData
      }

      const cache = getWorkspaceCache()
      const backlinkIndexReady = cache.hasFullIndex()
      const backlinks = backlinkIndexReady
        ? cache.getBacklinks(pathToDisplayPath(activeData.activeFile.relativePath))
        : []
      const existingProjectReferencePaths =
        await this.getExistingProjectReferencePaths(
          brainRoot,
          activeData.activeFile.relativePath
        )

      if (
        this.activeEditorVersion !== activeEditorVersion ||
        this.activeEditor?.document !== document
      ) {
        continue
      }

      return buildBrainContextWorkbenchData({
        activeFile: activeData.activeFile,
        backlinkIndexReady,
        backlinks,
        content: document?.getText() ?? "",
        existingProjectReferencePaths,
      })
    }
  }

  private async getExistingProjectReferencePaths(
    brainRoot: string,
    relativePath: string
  ): Promise<string[]> {
    const candidates = getProjectReferenceCandidates(relativePath)
    const existing = await Promise.all(
      candidates.map(async (candidate) => ({
        exists: await pathExists(path.join(brainRoot, candidate)),
        relativePath: candidate,
      }))
    )

    return existing
      .filter((candidate) => candidate.exists)
      .map((candidate) => candidate.relativePath)
  }

  private getSectionItems(
    section: BrainContextSection
  ): BrainContextWorkbenchItem[] {
    if (section.references.length === 0) {
      return [
        this.createEmptyItem(
          section.emptyMessage ?? "No context found",
          section.description
        ),
      ]
    }

    return section.references.map((reference) =>
      this.createReferenceItem(reference)
    )
  }

  private createSectionItem(
    section: BrainContextSection
  ): BrainContextWorkbenchItem {
    const item = new BrainContextWorkbenchItem(
      section.label,
      section.references.length > 0
        ? vscode.TreeItemCollapsibleState.Expanded
        : vscode.TreeItemCollapsibleState.Collapsed,
      {
        icon: this.iconForSection(section.id),
        itemType: "section",
        section,
      }
    )
    item.description = section.description
    return item
  }

  private createReferenceItem(
    reference: BrainContextReference
  ): BrainContextWorkbenchItem {
    const item = new BrainContextWorkbenchItem(
      reference.label,
      vscode.TreeItemCollapsibleState.None,
      {
        icon: this.iconForReference(reference),
        itemType: "reference",
        reference,
      }
    )
    item.description = reference.description
    item.tooltip =
      reference.relativePath ?? reference.reference ?? reference.url ?? reference.label
    const command = this.commandForReference(reference)
    if (command) {
      item.command = command
    }
    return item
  }

  private commandForReference(
    reference: BrainContextReference
  ): vscode.Command | undefined {
    if (reference.kind === "file" && reference.relativePath) {
      return {
        command: "vscode.open",
        title: "Open File",
        arguments: [vscode.Uri.file(path.join(getBrainPath(), reference.relativePath))],
      }
    }

    if (reference.kind === "url" && reference.url) {
      return {
        command: "vscode.open",
        title: "Open URL",
        arguments: [vscode.Uri.parse(reference.url)],
      }
    }

    if (reference.kind === "reference" && reference.reference) {
      return {
        command: "jonmagic.openDocumentByReference",
        title: "Open Reference",
        arguments: [{ reference: reference.reference }],
      }
    }

    return undefined
  }

  private iconForSection(sectionId: BrainContextSection["id"]): string {
    switch (sectionId) {
      case "frontmatter":
        return "references"
      case "sources":
        return "link-external"
      case "outgoing":
        return "link"
      case "backlinks":
        return "arrow-left"
      case "project":
        return "folder-library"
    }
  }

  private iconForReference(reference: BrainContextReference): string {
    switch (reference.kind) {
      case "file":
        return "file-text"
      case "url":
        return "link-external"
      case "reference":
        return reference.reference?.startsWith("uid:") ? "symbol-key" : "link"
    }
  }

  private createEmptyItem(
    label: string,
    description: string
  ): BrainContextWorkbenchItem {
    const item = new BrainContextWorkbenchItem(
      label,
      vscode.TreeItemCollapsibleState.None,
      {
        icon: "info",
        itemType: "empty",
      }
    )
    item.description = description
    return item
  }

  private createErrorItem(message: string): BrainContextWorkbenchItem {
    return new BrainContextWorkbenchItem(
      message,
      vscode.TreeItemCollapsibleState.None,
      {
        icon: "warning",
        itemType: "error",
      }
    )
  }
}
