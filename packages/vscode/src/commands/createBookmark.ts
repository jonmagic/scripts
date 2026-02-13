import * as vscode from "vscode"
import { createBookmark } from "@jonmagic/scripts-core"
import * as cp from "node:child_process"

async function generateAiSummary(url: string, title: string): Promise<string | undefined> {
  const prompt = `Summarize the content at ${url} (titled "${title}") in 1-3 sentences for a personal bookmark. Write in first person as if explaining why I saved it. Be concise and focus on what makes it interesting or useful. Return only the summary text, no quotes or formatting.`

  return new Promise((resolve) => {
    cp.exec(
      `copilot -p ${JSON.stringify(prompt)}`,
      { timeout: 30000 },
      (error, stdout) => {
        if (error || !stdout.trim()) {
          resolve(undefined)
        } else {
          resolve(stdout.trim())
        }
      }
    )
  })
}

export async function addBookmark(): Promise<void> {
  // Step 1: Get URL
  const url = await vscode.window.showInputBox({
    title: "Create Bookmark (1/3)",
    prompt: "URL to bookmark",
    placeHolder: "https://example.com/interesting-article",
    validateInput: (value) => {
      if (!value.trim()) return "URL is required"
      try {
        new URL(value.trim())
        return null
      } catch {
        return "Enter a valid URL"
      }
    },
  })

  if (!url?.trim()) return

  // Step 2: Get optional blurb
  const blurb = await vscode.window.showInputBox({
    title: "Create Bookmark (2/3)",
    prompt: "Your blurb (leave empty for AI summary)",
    placeHolder: "Why this is interesting...",
  })

  if (blurb === undefined) return // cancelled

  // Step 3: Get optional source
  const source = await vscode.window.showInputBox({
    title: "Create Bookmark (3/3)",
    prompt: "Where you found it (optional)",
    placeHolder: "hacker-news, slack, colleague...",
  })

  if (source === undefined) return // cancelled

  try {
    // Fetch page title
    let title: string | undefined
    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Creating bookmark...",
        cancellable: false,
      },
      async (progress) => {
        // Try to fetch the page title
        progress.report({ message: "Fetching page title..." })
        try {
          const response = await fetch(url.trim(), {
            signal: AbortSignal.timeout(10000),
            headers: { "User-Agent": "Mozilla/5.0 (Brain Bookmark)" },
          })
          const html = await response.text()
          const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)
          if (match?.[1]) {
            title = match[1].trim().replace(/\s+/g, " ")
          }
        } catch {
          // Title fetch is best-effort
        }

        // If no blurb provided, try AI summary
        let finalBlurb = blurb.trim() || undefined
        if (!finalBlurb) {
          progress.report({ message: "Generating AI summary..." })
          finalBlurb = await generateAiSummary(
            url.trim(),
            title || url.trim()
          )
        }

        const result = await createBookmark({
          url: url.trim(),
          title,
          blurb: finalBlurb,
          source: source.trim() || undefined,
        })

        // Open the created file
        const doc = await vscode.workspace.openTextDocument(
          vscode.Uri.file(result.filePath)
        )
        await vscode.window.showTextDocument(doc, { preview: false })

        vscode.window.showInformationMessage(
          `Bookmark created: ${result.title}`
        )
      }
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    await vscode.window.showErrorMessage(`Failed to create bookmark: ${message}`)
  }
}

export function registerCreateBookmarkCommand(
  context: vscode.ExtensionContext
): void {
  const disposable = vscode.commands.registerCommand(
    "jonmagic.createBookmark",
    addBookmark
  )
  context.subscriptions.push(disposable)
}
