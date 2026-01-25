// DocumentLinkProvider for wikilinks in markdown files.
// Makes [[...]] links clickable and navigable.

import * as vscode from "vscode"
import { WIKILINK_REGEX } from "@jonmagic/scripts-core"

export class WikilinkDocumentLinkProvider implements vscode.DocumentLinkProvider {
  provideDocumentLinks(
    document: vscode.TextDocument
  ): vscode.ProviderResult<vscode.DocumentLink[]> {
    const links: vscode.DocumentLink[] = []
    const text = document.getText()

    // Reset regex state
    const regex = new RegExp(WIKILINK_REGEX.source, "g")

    let match: RegExpExecArray | null
    while ((match = regex.exec(text)) !== null) {
      const startPos = document.positionAt(match.index)
      const endPos = document.positionAt(match.index + match[0].length)
      const range = new vscode.Range(startPos, endPos)

      // Extract the link target (first capture group)
      const target = match[1]
      if (!target) continue

      // Create a command URI to handle the link
      const commandUri = vscode.Uri.parse(
        `command:jonmagic.scripts.openDocumentByReference?${encodeURIComponent(
          JSON.stringify({ reference: target })
        )}`
      )

      const link = new vscode.DocumentLink(range, commandUri)
      link.tooltip = `Follow link to ${target}`
      links.push(link)
    }

    return links
  }
}
