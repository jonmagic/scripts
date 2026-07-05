import * as path from "node:path"
import * as vscode from "vscode"

import { getBrainPath } from "../config/brainPath"
import {
  BRAIN_FILE_CONTEXT_VALUE,
  getSidebarDayItemId,
  getSidebarSectionItemId,
  getActiveContextFile,
  getDailyProjectFiles,
  getRecentSidebarFiles,
  getWeekDayInfos,
  getWeeklyNoteFile,
  getWeeklyScheduleItems,
  type SidebarFileCandidate,
  type SidebarScheduleItem,
  type BrainSidebarSection,
} from "./brainSidebarData"
import { formatDate, getWeekLabel, getWeekStart } from "./weekUtils"

type BrainSidebarItemType =
  | "section"
  | "day"
  | "file"
  | "schedule"
  | "empty"
  | "error"

interface BrainSidebarItemOptions {
  date?: string
  icon?: string
  id?: string
  itemType?: BrainSidebarItemType
  resourceUri?: vscode.Uri
  sectionId?: BrainSidebarSection
}

export class BrainSidebarItem extends vscode.TreeItem {
  readonly date: string | undefined
  readonly itemType: BrainSidebarItemType
  readonly sectionId: BrainSidebarSection | undefined

  constructor(
    label: string,
    collapsibleState: vscode.TreeItemCollapsibleState,
    options: BrainSidebarItemOptions = {}
  ) {
    super(label, collapsibleState)
    this.date = options.date
    this.itemType = options.itemType ?? "section"
    this.sectionId = options.sectionId

    if (options.id) {
      this.id = options.id
    }

    if (options.icon) {
      this.iconPath = new vscode.ThemeIcon(options.icon)
    }

    if (options.resourceUri) {
      this.resourceUri = options.resourceUri
    }
  }
}

function getActiveEditorFilePath(
  editor: vscode.TextEditor | undefined
): string | undefined {
  if (editor?.document.uri.scheme !== "file") {
    return undefined
  }

  return editor.document.uri.fsPath
}

function parseDate(date: string): Date {
  const [yearPart, monthPart, dayPart] = date.split("-")
  const year = Number.parseInt(yearPart ?? "", 10)
  const month = Number.parseInt(monthPart ?? "", 10)
  const day = Number.parseInt(dayPart ?? "", 10)
  return new Date(year, month - 1, day)
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

export class BrainSidebarProvider implements vscode.TreeDataProvider<BrainSidebarItem> {
  private _onDidChangeTreeData: vscode.EventEmitter<BrainSidebarItem | undefined | null | void> =
    new vscode.EventEmitter<BrainSidebarItem | undefined | null | void>()
  readonly onDidChangeTreeData: vscode.Event<BrainSidebarItem | undefined | null | void> =
    this._onDidChangeTreeData.event

  private activeFilePath = getActiveEditorFilePath(vscode.window.activeTextEditor)
  private activeSectionItem: BrainSidebarItem | null = null
  private currentWeekStart: Date
  private recentFilesCache: BrainSidebarItem[] | null = null

  constructor() {
    this.currentWeekStart = getWeekStart(new Date())
    void this.updateNavigationContext()
  }

  private async weeklyNoteExists(weekStart: Date): Promise<boolean> {
    return (await getWeeklyNoteFile(getBrainPath(), weekStart)) !== null
  }

  private async updateNavigationContext(): Promise<void> {
    const prev = new Date(this.currentWeekStart)
    prev.setDate(prev.getDate() - 7)
    const next = new Date(this.currentWeekStart)
    next.setDate(next.getDate() + 7)

    const [hasPrev, hasNext] = await Promise.all([
      this.weeklyNoteExists(prev),
      this.weeklyNoteExists(next),
    ])

    await vscode.commands.executeCommand("setContext", "jonmagic.hasPreviousWeek", hasPrev)
    await vscode.commands.executeCommand("setContext", "jonmagic.hasNextWeek", hasNext)
  }

  setActiveEditor(editor: vscode.TextEditor | undefined): void {
    const nextFilePath = getActiveEditorFilePath(editor)
    if (nextFilePath === this.activeFilePath) {
      return
    }

    this.activeFilePath = nextFilePath
    this._onDidChangeTreeData.fire(this.activeSectionItem)
  }

  previousWeek(): void {
    const prev = new Date(this.currentWeekStart)
    prev.setDate(prev.getDate() - 7)
    this.currentWeekStart = prev
    this.refresh()
  }

  nextWeek(): void {
    const next = new Date(this.currentWeekStart)
    next.setDate(next.getDate() + 7)
    this.currentWeekStart = next
    this.refresh()
  }

  goToCurrentWeek(): void {
    this.currentWeekStart = getWeekStart(new Date())
    this.refresh()
  }

  refresh(): void {
    this.recentFilesCache = null
    void this.updateNavigationContext()
    this._onDidChangeTreeData.fire()
  }

  getTreeItem(element: BrainSidebarItem): vscode.TreeItem {
    return element
  }

  async getChildren(element?: BrainSidebarItem): Promise<BrainSidebarItem[]> {
    try {
      return await this.getChildrenOrThrow(element)
    } catch (error) {
      return [this.createErrorItem(errorMessage(error))]
    }
  }

  private async getChildrenOrThrow(
    element?: BrainSidebarItem
  ): Promise<BrainSidebarItem[]> {
    if (!element) {
      return this.getRootItems()
    }

    if (element.itemType === "day" && element.date) {
      return this.getDateItems(element.date, getWeekStart(parseDate(element.date)))
    }

    switch (element.sectionId) {
      case "today":
        return this.getTodayItems()
      case "week":
        return this.getWeekItems()
      case "recent":
        return this.getRecentItems()
      case "active":
        return this.getActiveContextItems()
      default:
        return []
    }
  }

  private async getRootItems(): Promise<BrainSidebarItem[]> {
    const brainPath = getBrainPath()
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(brainPath))
    } catch {
      const errorItem = this.createErrorItem("Brain folder not found")
      errorItem.description = "Configure in settings"
      errorItem.tooltip = `Configure "jonmagic.brainPath" in VS Code settings to point to your Brain folder. Current path: ${brainPath}`
      return [errorItem]
    }

    const activeSectionItem = this.createSectionItem(
      "Active Context",
      "active",
      "target",
      vscode.TreeItemCollapsibleState.Collapsed,
      "active Brain file"
    )
    this.activeSectionItem = activeSectionItem

    return [
      this.createSectionItem(
        `Today (${formatDate(new Date())})`,
        "today",
        "circle-filled",
        vscode.TreeItemCollapsibleState.Expanded,
        "meetings and daily projects"
      ),
      this.createSectionItem(
        getWeekLabel(this.currentWeekStart),
        "week",
        "calendar",
        vscode.TreeItemCollapsibleState.Collapsed,
        "weekly note and days"
      ),
      this.createSectionItem(
        "Recent Files",
        "recent",
        "history",
        vscode.TreeItemCollapsibleState.Collapsed,
        "bounded, recent-first"
      ),
      activeSectionItem,
    ]
  }

  private async getTodayItems(): Promise<BrainSidebarItem[]> {
    const today = new Date()
    return this.getDateItems(formatDate(today), getWeekStart(today))
  }

  private async getWeekItems(): Promise<BrainSidebarItem[]> {
    const brainRoot = getBrainPath()
    const weeklyNote = await getWeeklyNoteFile(brainRoot, this.currentWeekStart)
    const dayItems = getWeekDayInfos(this.currentWeekStart).map((day) => {
      const item = new BrainSidebarItem(
        `${day.dayName} (${day.date})`,
        vscode.TreeItemCollapsibleState.Collapsed,
        {
          date: day.date,
          icon: day.isToday ? "circle-filled" : "circle-outline",
          id: getSidebarDayItemId(day.date),
          itemType: "day",
        }
      )
      if (day.isToday) {
        item.description = "today"
      }
      return item
    })

    return [
      ...(weeklyNote ? [this.createFileItem(weeklyNote, "calendar")] : []),
      ...dayItems,
    ]
  }

  private async getDateItems(
    date: string,
    weekStart: Date
  ): Promise<BrainSidebarItem[]> {
    const brainRoot = getBrainPath()
    const [scheduleItems, projectFiles] = await Promise.all([
      getWeeklyScheduleItems(brainRoot, weekStart, date),
      getDailyProjectFiles(brainRoot, date),
    ])
    const items = [
      ...scheduleItems.map((item) => this.createScheduleItem(item)),
      ...projectFiles.map((file) => this.createFileItem(file)),
    ]

    if (items.length === 0) {
      return [
        this.createEmptyItem(
          `No meetings or Daily Projects found for ${date}`,
          "searched this date only"
        ),
      ]
    }

    return items
  }

  private async getRecentItems(): Promise<BrainSidebarItem[]> {
    if (!this.recentFilesCache) {
      const recentFiles = await getRecentSidebarFiles(getBrainPath())
      this.recentFilesCache = recentFiles.map((file) => this.createFileItem(file))
    }

    if (this.recentFilesCache.length === 0) {
      return [
        this.createEmptyItem(
          "No recent Brain Markdown files found",
          "searched bounded recent sources"
        ),
      ]
    }

    return this.recentFilesCache
  }

  private getActiveContextItems(): BrainSidebarItem[] {
    const activeFile = getActiveContextFile(getBrainPath(), this.activeFilePath)
    if (!activeFile) {
      return [
        this.createEmptyItem(
          "No active Brain Markdown file",
          "open a Brain note to populate this section"
        ),
      ]
    }

    return [this.createFileItem(activeFile, "target")]
  }

  private createSectionItem(
    label: string,
    sectionId: BrainSidebarSection,
    icon: string,
    collapsibleState: vscode.TreeItemCollapsibleState,
    description: string
  ): BrainSidebarItem {
    const item = new BrainSidebarItem(label, collapsibleState, {
      icon,
      id: getSidebarSectionItemId(sectionId),
      itemType: "section",
      sectionId,
    })
    item.description = description
    return item
  }

  private createFileItem(
    file: SidebarFileCandidate,
    icon = "file-text"
  ): BrainSidebarItem {
    const fileUri = vscode.Uri.file(file.absolutePath)
    const item = new BrainSidebarItem(
      file.label,
      vscode.TreeItemCollapsibleState.None,
      {
        icon,
        itemType: "file",
        resourceUri: fileUri,
      }
    )
    item.contextValue = BRAIN_FILE_CONTEXT_VALUE
    item.description = file.description
    item.tooltip = file.relativePath
    item.command = {
      command: "vscode.open",
      title: "Open File",
      arguments: [fileUri],
    }
    return item
  }

  private createScheduleItem(scheduleItem: SidebarScheduleItem): BrainSidebarItem {
    const label = `${scheduleItem.time} ${scheduleItem.description}`
    if (!scheduleItem.filePath) {
      return new BrainSidebarItem(label, vscode.TreeItemCollapsibleState.None, {
        icon: "clock",
        itemType: "schedule",
      })
    }

    const relativePath = path.relative(getBrainPath(), scheduleItem.filePath)
    return this.createFileItem(
      {
        absolutePath: scheduleItem.filePath,
        description: "meeting",
        label,
        relativePath,
      },
      "clock"
    )
  }

  private createEmptyItem(
    label: string,
    description: string
  ): BrainSidebarItem {
    const item = new BrainSidebarItem(label, vscode.TreeItemCollapsibleState.None, {
      icon: "info",
      itemType: "empty",
    })
    item.description = description
    return item
  }

  private createErrorItem(message: string): BrainSidebarItem {
    return new BrainSidebarItem(message, vscode.TreeItemCollapsibleState.None, {
      icon: "warning",
      itemType: "error",
    })
  }
}
