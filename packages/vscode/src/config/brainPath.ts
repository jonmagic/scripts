import * as os from "node:os"
import * as path from "node:path"
import * as vscode from "vscode"

export function normalizeRelativePath(relativePath: string): string {
  return relativePath.replace(/\\/g, "/")
}

export function expandHomePath(configuredPath: string): string {
  const trimmed = configuredPath.trim()

  if (trimmed === "~") {
    return os.homedir()
  }

  if (trimmed.startsWith("~/") || trimmed.startsWith("~\\")) {
    return path.join(os.homedir(), trimmed.slice(2))
  }

  return trimmed
}

export function getBrainPath(): string {
  const configuredPath = vscode.workspace
    .getConfiguration("jonmagic")
    .get<string>("brainPath", "~/Brain")

  const expandedPath = expandHomePath(configuredPath || "~/Brain")
  return path.resolve(expandedPath)
}

export function getBrainRootUri(): vscode.Uri {
  return vscode.Uri.file(getBrainPath())
}

export function getRelativeBrainPath(
  filePath: string,
  brainRoot = getBrainPath()
): string | null {
  const relativePath = path.relative(brainRoot, filePath)

  if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
    return null
  }

  return normalizeRelativePath(relativePath)
}
