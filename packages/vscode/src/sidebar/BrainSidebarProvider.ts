import * as fs from 'fs'
import * as path from 'path'
import * as vscode from 'vscode'
import { formatDate, getDayName, getWeekDays, getWeekLabel, getWeekStart } from './weekUtils'

/**
 * A schedule item parsed from the weekly note
 */
interface ScheduleItem {
  time: string        // e.g., "0900"
  description: string // e.g., "cubandera-dev" or "Snippets"
  filePath?: string   // Only set if it's a Meeting Notes wikilink
}

/**
 * Tree item representing an element in the Brain sidebar
 */
export class BrainSidebarItem extends vscode.TreeItem {
  constructor(
    public readonly label: string,
    public readonly collapsibleState: vscode.TreeItemCollapsibleState,
    public readonly itemType: 'week' | 'day' | 'file' | 'meeting' | 'error' = 'week',
    icon?: string,
    resourceUri?: vscode.Uri
  ) {
    super(label, collapsibleState)
    if (icon) {
      this.iconPath = new vscode.ThemeIcon(icon)
    }
    if (resourceUri) {
      this.resourceUri = resourceUri
    }
  }
}

/**
 * TreeDataProvider for the Brain sidebar view
 */
export class BrainSidebarProvider implements vscode.TreeDataProvider<BrainSidebarItem> {
  private _onDidChangeTreeData: vscode.EventEmitter<BrainSidebarItem | undefined | null | void> =
    new vscode.EventEmitter<BrainSidebarItem | undefined | null | void>()
  readonly onDidChangeTreeData: vscode.Event<BrainSidebarItem | undefined | null | void> =
    this._onDidChangeTreeData.event

  private currentWeekStart: Date
  private scheduleByDate: Map<string, ScheduleItem[]> = new Map()

  constructor() {
    this.currentWeekStart = getWeekStart(new Date())
    void this.updateNavigationContext()
  }

  /**
   * Check if a weekly note exists for a given week start date
   */
  private async weeklyNoteExists(weekStart: Date): Promise<boolean> {
    const brainPath = this.getBrainPath()
    const weekLabel = getWeekLabel(weekStart)
    const weeklyNotePath = path.join(brainPath, 'Weekly Notes', `${weekLabel}.md`)
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(weeklyNotePath))
      return true
    } catch {
      return false
    }
  }

  /**
   * Update context keys for navigation button visibility
   */
  private async updateNavigationContext(): Promise<void> {
    const prev = new Date(this.currentWeekStart)
    prev.setDate(prev.getDate() - 7)
    const next = new Date(this.currentWeekStart)
    next.setDate(next.getDate() + 7)

    const [hasPrev, hasNext] = await Promise.all([
      this.weeklyNoteExists(prev),
      this.weeklyNoteExists(next)
    ])

    await vscode.commands.executeCommand('setContext', 'jonmagic.hasPreviousWeek', hasPrev)
    await vscode.commands.executeCommand('setContext', 'jonmagic.hasNextWeek', hasNext)
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
    void this.updateNavigationContext()
    void this.parseScheduleFromWeeklyNote().then(schedule => {
      this.scheduleByDate = schedule
    })
    this._onDidChangeTreeData.fire()
  }

  private getBrainPath(): string {
    const config = vscode.workspace.getConfiguration('jonmagic')
    const configuredPath = config.get<string>('brainPath', '~/Brain')
    if (configuredPath.startsWith('~/')) {
      const homedir = process.env.HOME ?? ''
      return path.join(homedir, configuredPath.slice(2))
    }
    return configuredPath
  }

  /**
   * Get daily project files for a specific date
   */
  private async getDayProjectFiles(dateStr: string): Promise<BrainSidebarItem[]> {
    const brainPath = this.getBrainPath()
    const dayFolder = path.join(brainPath, 'Daily Projects', dateStr)
    const items: BrainSidebarItem[] = []

    try {
      const folderUri = vscode.Uri.file(dayFolder)
      const entries = await vscode.workspace.fs.readDirectory(folderUri)
      const files = entries
        .filter(([name, type]) => type === vscode.FileType.File && !name.startsWith('.'))
        .sort((a, b) => a[0].localeCompare(b[0]))

      for (const [name] of files) {
        const fileUri = vscode.Uri.file(path.join(dayFolder, name))
        const displayName = name.replace(/\.[^.]+$/, '')
        const item = new BrainSidebarItem(
          displayName,
          vscode.TreeItemCollapsibleState.None,
          'file',
          'file-text',
          fileUri
        )
        item.contextValue = 'file'
        item.command = {
          command: 'vscode.open',
          title: 'Open File',
          arguments: [fileUri]
        }
        items.push(item)
      }
    } catch {
      // Folder doesn't exist or error reading
    }

    return items
  }

  private async getWeeklyNotePath(): Promise<string | undefined> {
    const brainPath = this.getBrainPath()
    const weekLabel = getWeekLabel(this.currentWeekStart)
    const weeklyNotePath = path.join(brainPath, 'Weekly Notes', `${weekLabel}.md`)
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(weeklyNotePath))
      return weeklyNotePath
    } catch {
      return undefined
    }
  }

  /**
   * Parse schedule items from the weekly note
   */
  private async parseScheduleFromWeeklyNote(): Promise<Map<string, ScheduleItem[]>> {
    const weeklyNotePath = await this.getWeeklyNotePath()
    if (!weeklyNotePath) return new Map()

    const brainPath = this.getBrainPath()

    try {
      const content = await fs.promises.readFile(weeklyNotePath, 'utf-8')

      const scheduleMatch = content.match(/^## Schedule\s*$/m)
      if (!scheduleMatch || scheduleMatch.index === undefined) return new Map()

      const scheduleStart = scheduleMatch.index + scheduleMatch[0].length
      const nextSectionMatch = content.slice(scheduleStart).match(/^## /m)
      const scheduleContent = nextSectionMatch
        ? content.slice(scheduleStart, scheduleStart + nextSectionMatch.index!)
        : content.slice(scheduleStart)

      const scheduleByDate = new Map<string, ScheduleItem[]>()
      const meetingWikilinkPattern = /^\[\[Meeting Notes\/([^/]+)\/\d{4}-\d{2}-\d{2}\/([^\]|]+)(?:\|[^\]]+)?\]\]$/

      const lines = scheduleContent.split('\n')
      let currentDate: string | null = null

      for (const line of lines) {
        const dayMatch = line.match(/^- \w+ \((\d{4}-\d{2}-\d{2})\)/)
        if (dayMatch) {
          currentDate = dayMatch[1]!
          if (!scheduleByDate.has(currentDate)) {
            scheduleByDate.set(currentDate, [])
          }
          continue
        }

        if (currentDate) {
          const itemMatch = line.match(/^\t-\s*\[[ x]\]\s*(\d{4})\s*(.+)$/)
          if (itemMatch) {
            const time = itemMatch[1]!
            const descriptionPart = itemMatch[2]!.trim()
            const wikilinkMatch = descriptionPart.match(meetingWikilinkPattern)

            let scheduleItem: ScheduleItem
            if (wikilinkMatch) {
              const person = wikilinkMatch[1]!
              const noteNumber = wikilinkMatch[2]!
              const filePath = path.join(brainPath, 'Meeting Notes', person, currentDate, noteNumber + '.md')
              scheduleItem = { time, description: person, filePath }
            } else {
              scheduleItem = { time, description: descriptionPart }
            }

            scheduleByDate.get(currentDate)!.push(scheduleItem)
          }
        }
      }

      for (const items of scheduleByDate.values()) {
        items.sort((a, b) => a.time.localeCompare(b.time))
      }

      return scheduleByDate
    } catch {
      return new Map()
    }
  }

  /**
   * Get schedule items as tree items for a specific date
   */
  private getScheduleItems(dateStr: string): BrainSidebarItem[] {
    const scheduleItems = this.scheduleByDate.get(dateStr)
    if (!scheduleItems) return []

    return scheduleItems.map(scheduleItem => {
      const item = new BrainSidebarItem(
        `${scheduleItem.time} ${scheduleItem.description}`,
        vscode.TreeItemCollapsibleState.None,
        'meeting',
        'clock'
      )
      if (scheduleItem.filePath) {
        item.command = {
          command: 'vscode.open',
          title: 'Open Meeting Note',
          arguments: [vscode.Uri.file(scheduleItem.filePath)]
        }
      }
      return item
    })
  }

  getTreeItem(element: BrainSidebarItem): vscode.TreeItem {
    return element
  }

  async getChildren(element?: BrainSidebarItem): Promise<BrainSidebarItem[]> {
    // Root level: week header + 7 day rows
    if (!element) {
      const brainPath = this.getBrainPath()
      try {
        await vscode.workspace.fs.stat(vscode.Uri.file(brainPath))
      } catch {
        const errorItem = new BrainSidebarItem(
          'Brain folder not found',
          vscode.TreeItemCollapsibleState.None,
          'error',
          'warning'
        )
        errorItem.description = 'Configure in settings'
        errorItem.tooltip = `Configure "jonmagic.brainPath" in VS Code settings to point to your Brain folder. Current path: ${brainPath}`
        return [errorItem]
      }

      const items: BrainSidebarItem[] = []

      // Week header (clickable if weekly note exists)
      const weekLabel = getWeekLabel(this.currentWeekStart)
      const weeklyNotePath = await this.getWeeklyNotePath()
      const weekHeader = new BrainSidebarItem(
        weekLabel,
        vscode.TreeItemCollapsibleState.None,
        'week',
        'calendar'
      )
      if (weeklyNotePath) {
        weekHeader.command = {
          command: 'vscode.open',
          title: 'Open Weekly Note',
          arguments: [vscode.Uri.file(weeklyNotePath)]
        }
      }
      items.push(weekHeader)

      // Parse schedule for the week
      this.scheduleByDate = await this.parseScheduleFromWeeklyNote()

      // Add a row for each day of the week (Sun-Sat)
      const todayStr = formatDate(new Date())
      const weekDays = getWeekDays(this.currentWeekStart)
      for (const day of weekDays) {
        const dateStr = formatDate(day)
        const dayName = getDayName(day)
        const isToday = dateStr === todayStr
        const collapsibleState = isToday
          ? vscode.TreeItemCollapsibleState.Expanded
          : vscode.TreeItemCollapsibleState.Collapsed
        const dayItem = new BrainSidebarItem(
          `${dayName} (${dateStr})`,
          collapsibleState,
          'day',
          isToday ? 'circle-filled' : 'circle-outline'
        )
        dayItem.contextValue = dateStr
        if (isToday) {
          dayItem.description = 'today'
        }
        items.push(dayItem)
      }

      return items
    }

    // Day level: meetings first (chronological), then daily project files
    if (element.itemType === 'day' && element.contextValue) {
      const dateStr = element.contextValue
      const meetings = this.getScheduleItems(dateStr)
      const projects = await this.getDayProjectFiles(dateStr)
      return [...meetings, ...projects]
    }

    return []
  }
}
