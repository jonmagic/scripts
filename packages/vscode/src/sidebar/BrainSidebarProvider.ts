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
    public readonly itemType: 'week' | 'day' | 'file' | 'section' | 'meeting' | 'error' = 'week',
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

  /**
   * Navigate to the previous week
   */
  previousWeek(): void {
    const prev = new Date(this.currentWeekStart)
    prev.setDate(prev.getDate() - 7)
    this.currentWeekStart = prev
    this.refresh()
  }

  /**
   * Navigate to the next week
   */
  nextWeek(): void {
    const next = new Date(this.currentWeekStart)
    next.setDate(next.getDate() + 7)
    this.currentWeekStart = next
    this.refresh()
  }

  /**
   * Reset to the current week
   */
  goToCurrentWeek(): void {
    this.currentWeekStart = getWeekStart(new Date())
    this.refresh()
  }

  /**
   * Refresh the tree view
   */
  refresh(): void {
    // Update navigation context for button visibility
    void this.updateNavigationContext()
    // Refresh schedule from weekly note when tree refreshes
    void this.parseScheduleFromWeeklyNote().then(schedule => {
      this.scheduleByDate = schedule
    })
    this._onDidChangeTreeData.fire()
  }

  /**
   * Get the configured Brain folder path
   */
  private getBrainPath(): string {
    const config = vscode.workspace.getConfiguration('jonmagic')
    const configuredPath = config.get<string>('brainPath', '~/Brain')
    // Expand ~ to home directory
    if (configuredPath.startsWith('~/')) {
      const homedir = process.env.HOME ?? ''
      return path.join(homedir, configuredPath.slice(2))
    }
    return configuredPath
  }

  /**
   * Get Daily Projects items for the current week
   */
  private async getDailyProjectItems(): Promise<BrainSidebarItem[]> {
    const brainPath = this.getBrainPath()
    const weekDays = getWeekDays(this.currentWeekStart)
    const items: BrainSidebarItem[] = []

    for (const day of weekDays) {
      const dateStr = formatDate(day)
      const dayFolder = path.join(brainPath, 'Daily Projects', dateStr)

      try {
        const folderUri = vscode.Uri.file(dayFolder)
        const entries = await vscode.workspace.fs.readDirectory(folderUri)
        const files = entries
          .filter(([name, type]) => type === vscode.FileType.File && !name.startsWith('.'))
          .sort((a, b) => a[0].localeCompare(b[0]))

        if (files.length > 0) {
          const dayName = getDayName(day)
          const dayHeader = new BrainSidebarItem(
            `${dayName} (${dateStr})`,
            vscode.TreeItemCollapsibleState.Collapsed,
            'day',
            'folder'
          )
          dayHeader.contextValue = dateStr // Store date for getChildren lookup
          items.push(dayHeader)
        }
      } catch {
        // Folder doesn't exist, skip
      }
    }

    return items
  }

  /**
   * Get the files in a Daily Projects day folder
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
          'file',
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

  /**
   * Find the weekly note file for the current week
   */
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
   * Finds the "## Schedule" section and parses day headers with their schedule items
   */
  private async parseScheduleFromWeeklyNote(): Promise<Map<string, ScheduleItem[]>> {
    const weeklyNotePath = await this.getWeeklyNotePath()
    if (!weeklyNotePath) return new Map()

    const brainPath = this.getBrainPath()

    try {
      const content = await fs.promises.readFile(weeklyNotePath, 'utf-8')

      // Find the Schedule section
      const scheduleMatch = content.match(/^## Schedule\s*$/m)
      if (!scheduleMatch || scheduleMatch.index === undefined) return new Map()

      // Get content from Schedule section until next ## header or end
      const scheduleStart = scheduleMatch.index + scheduleMatch[0].length
      const nextSectionMatch = content.slice(scheduleStart).match(/^## /m)
      const scheduleContent = nextSectionMatch
        ? content.slice(scheduleStart, scheduleStart + nextSectionMatch.index!)
        : content.slice(scheduleStart)

      const scheduleByDate = new Map<string, ScheduleItem[]>()

      // Pattern for Meeting Notes wikilink
      const meetingWikilinkPattern = /^\[\[Meeting Notes\/([^/]+)\/\d{4}-\d{2}-\d{2}\/([^\]|]+)(?:\|[^\]]+)?\]\]$/

      // Split content into day sections
      const lines = scheduleContent.split('\n')
      let currentDate: string | null = null

      for (const line of lines) {
        // Check for day header
        const dayMatch = line.match(/^- \w+ \((\d{4}-\d{2}-\d{2})\)/)
        if (dayMatch) {
          currentDate = dayMatch[1]!
          if (!scheduleByDate.has(currentDate)) {
            scheduleByDate.set(currentDate, [])
          }
          continue
        }

        // Check for schedule item (must have a current date)
        if (currentDate) {
          const itemMatch = line.match(/^\t-\s*\[[ x]\]\s*(\d{4})\s*(.+)$/)
          if (itemMatch) {
            const time = itemMatch[1]!
            const descriptionPart = itemMatch[2]!.trim()

            // Check if it's a Meeting Notes wikilink
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

      // Sort schedule items by time within each date
      for (const items of scheduleByDate.values()) {
        items.sort((a, b) => a.time.localeCompare(b.time))
      }

      return scheduleByDate
    } catch {
      return new Map()
    }
  }

  getTreeItem(element: BrainSidebarItem): vscode.TreeItem {
    return element
  }

  async getChildren(element?: BrainSidebarItem): Promise<BrainSidebarItem[]> {
    // Root level: return week header, weekly note, and daily projects
    if (!element) {
      // Check if Brain folder exists
      const brainPath = this.getBrainPath()
      try {
        await vscode.workspace.fs.stat(vscode.Uri.file(brainPath))
      } catch {
        // Brain folder doesn't exist, show a helpful message
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

      // Schedule section header (collapsible) - always show for current/past weeks with content
      this.scheduleByDate = await this.parseScheduleFromWeeklyNote()
      if (this.scheduleByDate.size > 0) {
        const scheduleSection = new BrainSidebarItem(
          'Schedule',
          vscode.TreeItemCollapsibleState.Collapsed,
          'section',
          'list-unordered'
        )
        scheduleSection.contextValue = 'schedule-section'
        items.push(scheduleSection)
      }

      // Daily Projects section header - always show
      const dailyProjectsSection = new BrainSidebarItem(
        'Daily Projects',
        vscode.TreeItemCollapsibleState.Collapsed,
        'section',
        'folder-library'
      )
      dailyProjectsSection.contextValue = 'daily-projects-section'
      items.push(dailyProjectsSection)

      return items
    }

    // Schedule section: return day headers for days with schedule items
    if (element.itemType === 'section' && element.contextValue === 'schedule-section') {
      return this.getScheduleDayHeaders()
    }

    // Schedule day: return individual schedule items for that day
    if (element.itemType === 'day' && element.contextValue?.startsWith('schedule-day:')) {
      const dateStr = element.contextValue.replace('schedule-day:', '')
      return this.getScheduleItems(dateStr)
    }

    // Daily Projects section: return day folders
    if (element.itemType === 'section' && element.contextValue === 'daily-projects-section') {
      return this.getDailyProjectItems()
    }

    // Day items: return files for that day (Daily Projects)
    if (element.itemType === 'day' && element.contextValue && !element.contextValue.startsWith('schedule-day:')) {
      return this.getDayProjectFiles(element.contextValue)
    }

    return []
  }

  /**
   * Get day headers for days that have schedule items
   */
  private getScheduleDayHeaders(): BrainSidebarItem[] {
    const weekDays = getWeekDays(this.currentWeekStart)
    const items: BrainSidebarItem[] = []

    for (const day of weekDays) {
      const dateStr = formatDate(day)
      const scheduleItems = this.scheduleByDate.get(dateStr)

      if (scheduleItems && scheduleItems.length > 0) {
        const dayName = getDayName(day)
        const dayHeader = new BrainSidebarItem(
          `${dayName} (${dateStr})`,
          vscode.TreeItemCollapsibleState.Collapsed,
          'day',
          'calendar'
        )
        dayHeader.contextValue = `schedule-day:${dateStr}`
        items.push(dayHeader)
      }
    }

    return items
  }

  /**
   * Get individual schedule items for a specific date
   */
  private getScheduleItems(dateStr: string): BrainSidebarItem[] {
    const scheduleItems = this.scheduleByDate.get(dateStr)
    if (!scheduleItems) return []

    return scheduleItems.map(scheduleItem => {
      const hasFile = !!scheduleItem.filePath
      const item = new BrainSidebarItem(
        `${scheduleItem.time} ${scheduleItem.description}`,
        vscode.TreeItemCollapsibleState.None,
        'meeting',
        hasFile ? 'person' : 'clock',
        hasFile ? vscode.Uri.file(scheduleItem.filePath!) : undefined
      )
      if (hasFile) {
        item.command = {
          command: 'vscode.open',
          title: 'Open Meeting Note',
          arguments: [vscode.Uri.file(scheduleItem.filePath!)]
        }
      }
      return item
    })
  }
}
