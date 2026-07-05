import type { Dirent } from "node:fs"
import * as fs from "node:fs/promises"
import * as path from "node:path"
import * as vscode from "vscode"
import {
  appendProjectReference,
  appendWeeklyNoteTodo,
  createPathWikilinkForFile,
  createUidWikilinkForFile,
  extractMarkdownLevelTwoHeadings,
} from "@jonmagic/scripts-core"

import { getWorkspaceCache } from "../cache/workspaceCache"
import { getBrainPath, getRelativeBrainPath } from "../config/brainPath"

type ResourceTarget = vscode.Uri | { resourceUri?: vscode.Uri }

interface ProjectReferencesQuickPickItem extends vscode.QuickPickItem {
  referencesPath: string
}

interface HeadingQuickPickItem extends vscode.QuickPickItem {
  heading: string
}

interface ErrorWithCode extends Error {
  code?: string
}

function isErrorWithCode(error: unknown): error is ErrorWithCode {
  return error instanceof Error && "code" in error
}

function getResourceUri(target?: ResourceTarget): vscode.Uri | undefined {
  if (!target) {
    return undefined
  }

  if (target instanceof vscode.Uri) {
    return target
  }

  return target.resourceUri
}

function getCommandResourceUri(target?: ResourceTarget): vscode.Uri | undefined {
  return getResourceUri(target) ?? vscode.window.activeTextEditor?.document.uri
}

async function showActionError(prefix: string, error: unknown): Promise<void> {
  const message = error instanceof Error ? error.message : String(error)
  await vscode.window.showErrorMessage(`${prefix}: ${message}`)
}

async function copyPathWikilink(target?: ResourceTarget): Promise<void> {
  const resourceUri = getCommandResourceUri(target)
  if (!resourceUri || resourceUri.scheme !== "file") {
    await vscode.window.showErrorMessage("No Brain file selected")
    return
  }

  try {
    const result = await createPathWikilinkForFile({
      brainRoot: getBrainPath(),
      filePath: resourceUri.fsPath,
    })
    await vscode.env.clipboard.writeText(result.wikilink)
    await vscode.window.showInformationMessage(
      `Path wikilink copied: ${result.displayPath}`
    )
  } catch (error) {
    await showActionError("Could not copy path wikilink", error)
  }
}

async function copyUidWikilink(target?: ResourceTarget): Promise<void> {
  const resourceUri = getCommandResourceUri(target)
  if (!resourceUri || resourceUri.scheme !== "file") {
    await vscode.window.showErrorMessage("No Brain file selected")
    return
  }

  try {
    const result = await createUidWikilinkForFile({
      brainRoot: getBrainPath(),
      filePath: resourceUri.fsPath,
    })
    await vscode.env.clipboard.writeText(result.wikilink)
    await vscode.window.showInformationMessage(
      `UID wikilink copied: ${result.displayPath}`
    )
  } catch (error) {
    await showActionError("Could not copy UID wikilink", error)
  }
}

async function appendWeeklyTodo(): Promise<void> {
  const text = await vscode.window.showInputBox({
    title: "Append Weekly Note TODO",
    prompt: "TODO text for the current Weekly Note",
    placeHolder: "Follow up on typed Brain actions",
    validateInput: (value) => {
      return value.trim() ? null : "TODO text is required"
    },
  })

  if (text === undefined) {
    return
  }

  try {
    const result = await appendWeeklyNoteTodo({
      brainRoot: getBrainPath(),
      text,
    })
    const action = result.alreadyPresent ? "already present" : "added"
    await vscode.window.showInformationMessage(`Weekly TODO ${action}`)
  } catch (error) {
    await showActionError("Could not append Weekly Note TODO", error)
  }
}

async function collectProjectReferencesFiles(
  brainRoot: string
): Promise<ProjectReferencesQuickPickItem[]> {
  const projectsRoot = path.join(brainRoot, "Projects")
  const results: ProjectReferencesQuickPickItem[] = []

  async function walk(directoryPath: string, depth: number): Promise<void> {
    if (depth > 4) {
      return
    }

    let entries: Dirent[]
    try {
      entries = await fs.readdir(directoryPath, { withFileTypes: true })
    } catch (error) {
      if (isErrorWithCode(error) && error.code === "ENOENT") {
        return
      }

      throw error
    }

    for (const entry of entries) {
      if (entry.name.startsWith(".")) {
        continue
      }

      const entryPath = path.join(directoryPath, entry.name)
      if (entry.isFile() && entry.name === "references.md") {
        const relativePath = getRelativeBrainPath(entryPath, brainRoot)
        if (!relativePath) {
          continue
        }

        const projectPath = path.dirname(relativePath).replace(/^Projects\//, "")
        results.push({
          label: projectPath,
          detail: relativePath,
          referencesPath: entryPath,
        })
        continue
      }

      if (entry.isDirectory()) {
        await walk(entryPath, depth + 1)
      }
    }
  }

  await walk(projectsRoot, 0)

  return results.sort((left, right) => left.label.localeCompare(right.label))
}

async function selectProjectReferencesFile(
  brainRoot: string
): Promise<string | undefined> {
  const items = await collectProjectReferencesFiles(brainRoot)
  if (items.length === 0) {
    await vscode.window.showErrorMessage("No Projects/*/references.md files found")
    return undefined
  }

  const selected = await vscode.window.showQuickPick(items, {
    title: "Add Reference to Project",
    placeHolder: "Choose the Project references.md file",
    matchOnDescription: true,
    matchOnDetail: true,
  })

  return selected?.referencesPath
}

async function selectProjectReferenceHeading(
  referencesPath: string
): Promise<string | undefined> {
  const content = await fs.readFile(referencesPath, "utf8")
  const headings = extractMarkdownLevelTwoHeadings(content)
  if (headings.length === 0) {
    await vscode.window.showErrorMessage(
      `${path.basename(path.dirname(referencesPath))}/references.md has no level-two headings`
    )
    return undefined
  }

  const selected = await vscode.window.showQuickPick(
    headings.map((heading): HeadingQuickPickItem => ({ label: heading, heading })),
    {
      title: "Add Reference to Project",
      placeHolder: "Choose the references.md heading to append under",
      matchOnDescription: true,
      matchOnDetail: true,
    }
  )

  return selected?.heading
}

async function promptUrlReference(): Promise<string | undefined> {
  const url = await vscode.window.showInputBox({
    title: "Add URL to Project References",
    prompt: "URL to append",
    placeHolder: "https://example.com/reference",
    validateInput: (value) => {
      if (!value.trim()) {
        return "URL is required"
      }

      try {
        new URL(value.trim())
        return null
      } catch {
        return "Enter a valid URL"
      }
    },
  })

  if (url === undefined) {
    return undefined
  }

  const label = await vscode.window.showInputBox({
    title: "Add URL to Project References",
    prompt: "Optional label",
    placeHolder: "Reference title",
  })

  if (label === undefined) {
    return undefined
  }

  const normalizedUrl = url.trim()
  const normalizedLabel = label.trim()
  return normalizedLabel ? `[${normalizedLabel}](${normalizedUrl})` : normalizedUrl
}

async function resolveReferenceFromSelection(
  target?: ResourceTarget
): Promise<string | undefined> {
  const resourceUri = getCommandResourceUri(target)
  const brainRoot = getBrainPath()

  if (resourceUri?.scheme === "file") {
    try {
      const result = await createPathWikilinkForFile({
        brainRoot,
        filePath: resourceUri.fsPath,
      })
      return result.wikilink
    } catch (error) {
      const isExplicitSelection = target !== undefined
      const isActiveBrainPath =
        getRelativeBrainPath(resourceUri.fsPath, brainRoot) !== null

      if (isExplicitSelection || isActiveBrainPath) {
        throw error
      }
    }
  }

  return promptUrlReference()
}

async function addReferenceToProject(target?: ResourceTarget): Promise<void> {
  try {
    const reference = await resolveReferenceFromSelection(target)
    if (!reference) {
      return
    }

    const brainRoot = getBrainPath()
    const referencesPath = await selectProjectReferencesFile(brainRoot)
    if (!referencesPath) {
      return
    }

    const heading = await selectProjectReferenceHeading(referencesPath)
    if (!heading) {
      return
    }

    const result = await appendProjectReference({
      brainRoot,
      referencesPath,
      heading,
      reference,
    })
    const action = result.alreadyPresent ? "already present" : "added"
    await vscode.window.showInformationMessage(`Project reference ${action}`)
  } catch (error) {
    await showActionError("Could not add Project reference", error)
  }
}

async function rebuildBrainIndex(refreshSidebar: () => void): Promise<void> {
  try {
    const cache = getWorkspaceCache()
    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Rebuilding Brain index...",
        cancellable: false,
      },
      async () => {
        await cache.refresh()
      }
    )
    refreshSidebar()
    await vscode.window.showInformationMessage(
      `Brain index rebuilt: ${cache.getMarkdownFiles().length} Markdown files indexed`
    )
  } catch (error) {
    await showActionError("Could not rebuild Brain index", error)
  }
}

export function registerTypedBrainActionCommands(
  context: vscode.ExtensionContext,
  refreshSidebar: () => void
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand(
      "jonmagic.copyPathWikilink",
      copyPathWikilink
    ),
    vscode.commands.registerCommand("jonmagic.copyUidWikilink", copyUidWikilink),
    vscode.commands.registerCommand("jonmagic.appendWeeklyTodo", appendWeeklyTodo),
    vscode.commands.registerCommand(
      "jonmagic.addReferenceToProject",
      addReferenceToProject
    ),
    vscode.commands.registerCommand("jonmagic.rebuildIndex", () =>
      rebuildBrainIndex(refreshSidebar)
    )
  )
}
