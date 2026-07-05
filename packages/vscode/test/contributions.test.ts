import { describe, expect, test } from "bun:test"
import * as fs from "node:fs/promises"
import * as path from "node:path"

interface CommandContribution {
  command: string
  title: string
}

interface ViewContribution {
  id: string
}

interface ViewContainerContribution {
  id: string
}

interface MenuContribution {
  command: string
}

interface VscodePackageJson {
  activationEvents?: string[]
  contributes: {
    commands: CommandContribution[]
    menus?: Record<string, MenuContribution[]>
    views?: Record<string, ViewContribution[]>
    viewsContainers?: Record<string, ViewContainerContribution[]>
  }
}

const packageRoot = path.resolve(import.meta.dirname, "..")
const sourceRoot = path.join(packageRoot, "src")
const builtInViewContainers = new Set([
  "debug",
  "explorer",
  "extensions",
  "scm",
  "test",
])
const internalCommands = new Set(["jonmagic.openDocumentByReference"])

async function readSourceTree(directory: string): Promise<string> {
  const entries = await fs.readdir(directory, { withFileTypes: true })
  const contents = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = path.join(directory, entry.name)
      if (entry.isDirectory()) {
        return readSourceTree(entryPath)
      }

      if (!entry.isFile() || !entry.name.endsWith(".ts")) {
        return ""
      }

      return fs.readFile(entryPath, "utf8")
    })
  )

  return contents.join("\n")
}

describe("VS Code contributions", () => {
  test("keeps command, menu, activation, and view IDs wired to source", async () => {
    const packageJson = JSON.parse(
      await fs.readFile(path.join(packageRoot, "package.json"), "utf8")
    ) as VscodePackageJson
    const sourceText = await readSourceTree(sourceRoot)
    const contributedCommands = new Set(
      packageJson.contributes.commands.map((command) => command.command)
    )
    const registeredCommands = new Set(
      [...sourceText.matchAll(/registerCommand\(\s*["']([^"']+)["']/g)].map(
        (match) => match[1]
      )
    )
    const registeredViews = new Set(
      [
        ...sourceText.matchAll(
          /registerTreeDataProvider\(\s*["']([^"']+)["']/g
        ),
      ].map((match) => match[1])
    )
    const contributedViewContainers = new Set(
      Object.values(packageJson.contributes.viewsContainers ?? {})
        .flat()
        .map((container) => container.id)
    )

    for (const command of contributedCommands) {
      expect(registeredCommands.has(command)).toBe(true)
    }

    for (const command of registeredCommands) {
      expect(contributedCommands.has(command) || internalCommands.has(command)).toBe(
        true
      )
    }

    for (const event of packageJson.activationEvents ?? []) {
      if (!event.startsWith("onCommand:")) {
        continue
      }

      expect(contributedCommands.has(event.slice("onCommand:".length))).toBe(
        true
      )
    }

    for (const menuItems of Object.values(packageJson.contributes.menus ?? {})) {
      for (const item of menuItems) {
        expect(contributedCommands.has(item.command)).toBe(true)
      }
    }

    for (const [containerId, views] of Object.entries(
      packageJson.contributes.views ?? {}
    )) {
      if (!builtInViewContainers.has(containerId)) {
        expect(contributedViewContainers.has(containerId)).toBe(true)
      }

      for (const view of views) {
        expect(registeredViews.has(view.id)).toBe(true)
      }
    }
  })

  test("keeps Brain commands user-facing as Brain commands", async () => {
    const packageJson = JSON.parse(
      await fs.readFile(path.join(packageRoot, "package.json"), "utf8")
    ) as VscodePackageJson

    for (const command of packageJson.contributes.commands) {
      expect(command.title.startsWith("Jonmagic:")).toBe(false)
    }
  })
})
