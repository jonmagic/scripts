import * as vscode from "vscode"

import { getBrainPath } from "../config/brainPath"
import {
  getBrainCollectionCandidates,
  type BrainCollection,
  type BrainCollectionCandidate,
} from "./brainCollectionQuickPickCandidates"

interface BrainCollectionQuickPickItem extends vscode.QuickPickItem {
  absolutePath: string
}

function buildQuickPickItems(
  candidates: BrainCollectionCandidate[]
): BrainCollectionQuickPickItem[] {
  return candidates.map((candidate) => ({
    label: candidate.label,
    description: candidate.description,
    detail: candidate.detail,
    absolutePath: candidate.absolutePath,
  }))
}

async function openBrainCollectionQuickPick(
  collection: BrainCollection
): Promise<void> {
  const brainRoot = getBrainPath()
  let result

  try {
    result = await getBrainCollectionCandidates(brainRoot, collection)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    await vscode.window.showErrorMessage(message)
    return
  }

  const items = buildQuickPickItems(result.candidates)

  if (items.length === 0) {
    await vscode.window.showInformationMessage(result.emptyMessage)
    return
  }

  const selected = await vscode.window.showQuickPick(items, {
    title: result.title,
    placeHolder: result.placeHolder,
    matchOnDescription: true,
    matchOnDetail: true,
  })

  if (!selected) {
    return
  }

  const document = await vscode.workspace.openTextDocument(
    vscode.Uri.file(selected.absolutePath)
  )
  await vscode.window.showTextDocument(document, { preview: false })
}

export function registerBrainCollectionQuickPickCommands(
  context: vscode.ExtensionContext
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand("jonmagic.openDailyProject", () =>
      openBrainCollectionQuickPick("dailyProjects")
    ),
    vscode.commands.registerCommand("jonmagic.openWeeklyNote", () =>
      openBrainCollectionQuickPick("weeklyNotes")
    ),
    vscode.commands.registerCommand("jonmagic.openProjectNote", () =>
      openBrainCollectionQuickPick("projectNotes")
    ),
    vscode.commands.registerCommand("jonmagic.openMeetingNote", () =>
      openBrainCollectionQuickPick("meetingNotes")
    ),
    vscode.commands.registerCommand("jonmagic.openBookmark", () =>
      openBrainCollectionQuickPick("bookmarks")
    )
  )
}
