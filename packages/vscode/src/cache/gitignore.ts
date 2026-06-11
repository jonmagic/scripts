import * as fs from "node:fs/promises"
import * as path from "node:path"

interface IgnoreRule {
  basePath: string
  pattern: string
  negated: boolean
  directoryOnly: boolean
  anchored: boolean
  hasSlash: boolean
  regex: RegExp
}

export class GitignoreMatcher {
  private readonly rootPath: string
  private readonly rulesByDirectory = new Map<string, Promise<IgnoreRule[]>>()

  constructor(rootPath: string) {
    this.rootPath = path.resolve(rootPath)
  }

  clearCache(): void {
    this.rulesByDirectory.clear()
  }

  async isIgnored(
    absolutePath: string,
    options: { isDirectory?: boolean } = {}
  ): Promise<boolean> {
    const targetPath = path.resolve(absolutePath)
    if (!isInsideOrEqual(this.rootPath, targetPath)) {
      return false
    }

    const isDirectory = options.isDirectory ?? false
    const ancestorDirectories = getAncestorDirectories(
      this.rootPath,
      targetPath,
      isDirectory
    )

    for (const directoryPath of ancestorDirectories) {
      if (await this.matchesPath(directoryPath, true)) {
        return true
      }
    }

    return this.matchesPath(targetPath, isDirectory)
  }

  private async matchesPath(
    absolutePath: string,
    isDirectory: boolean
  ): Promise<boolean> {
    const rules = await this.getRulesForPath(absolutePath)
    let ignored = false

    for (const rule of rules) {
      if (matchesRule(rule, absolutePath, isDirectory)) {
        ignored = !rule.negated
      }
    }

    return ignored
  }

  private async getRulesForPath(absolutePath: string): Promise<IgnoreRule[]> {
    const parentDirectories = getRuleDirectories(this.rootPath, absolutePath)
    const ruleSets = await Promise.all(
      parentDirectories.map((directoryPath) => this.loadRules(directoryPath))
    )

    return ruleSets.flat()
  }

  private loadRules(directoryPath: string): Promise<IgnoreRule[]> {
    const cachedRules = this.rulesByDirectory.get(directoryPath)
    if (cachedRules) {
      return cachedRules
    }

    const rules = fs
      .readFile(path.join(directoryPath, ".gitignore"), "utf-8")
      .then((content) => parseGitignore(content, directoryPath))
      .catch((error: unknown) => {
        if (
          error instanceof Error &&
          "code" in error &&
          (error as NodeJS.ErrnoException).code === "ENOENT"
        ) {
          return []
        }

        throw error
      })

    this.rulesByDirectory.set(directoryPath, rules)
    return rules
  }
}

function parseGitignore(content: string, basePath: string): IgnoreRule[] {
  const rules: IgnoreRule[] = []

  for (const rawLine of content.split(/\r?\n/)) {
    let pattern = trimUnescapedTrailingWhitespace(rawLine)
    if (pattern === "" || pattern.startsWith("#")) {
      continue
    }

    let negated = false
    if (pattern.startsWith("\\#") || pattern.startsWith("\\!")) {
      pattern = pattern.slice(1)
    } else if (pattern.startsWith("!")) {
      negated = true
      pattern = pattern.slice(1)
    }

    if (pattern === "") {
      continue
    }

    let directoryOnly = false
    if (pattern.endsWith("/") && !isEscaped(pattern, pattern.length - 1)) {
      directoryOnly = true
      pattern = pattern.slice(0, -1)
    }

    let anchored = false
    while (pattern.startsWith("/")) {
      anchored = true
      pattern = pattern.slice(1)
    }

    if (pattern === "") {
      continue
    }

    const hasSlash = pattern.includes("/")
    rules.push({
      basePath,
      pattern,
      negated,
      directoryOnly,
      anchored,
      hasSlash,
      regex: globToRegExp(pattern),
    })
  }

  return rules
}

function matchesRule(
  rule: IgnoreRule,
  absolutePath: string,
  isDirectory: boolean
): boolean {
  if (rule.directoryOnly && !isDirectory) {
    return false
  }

  const relativePath = toPosix(path.relative(rule.basePath, absolutePath))
  if (
    relativePath === "" ||
    relativePath.startsWith("../") ||
    path.isAbsolute(relativePath)
  ) {
    return false
  }

  if (rule.anchored || rule.hasSlash) {
    return rule.regex.test(relativePath)
  }

  return rule.regex.test(path.posix.basename(relativePath))
}

function getRuleDirectories(rootPath: string, absolutePath: string): string[] {
  const parentPath = path.dirname(absolutePath)
  if (!isInsideOrEqual(rootPath, parentPath)) {
    return []
  }

  const relativeParentPath = toPosix(path.relative(rootPath, parentPath))
  if (relativeParentPath === "") {
    return [rootPath]
  }

  const directories = [rootPath]
  let currentPath = rootPath

  for (const part of relativeParentPath.split("/")) {
    currentPath = path.join(currentPath, part)
    directories.push(currentPath)
  }

  return directories
}

function getAncestorDirectories(
  rootPath: string,
  targetPath: string,
  isDirectory: boolean
): string[] {
  const relativePath = toPosix(path.relative(rootPath, targetPath))
  if (
    relativePath === "" ||
    relativePath.startsWith("../") ||
    path.isAbsolute(relativePath)
  ) {
    return []
  }

  const parts = relativePath.split("/")
  const directoryParts = isDirectory ? parts : parts.slice(0, -1)
  const directories: string[] = []
  let currentPath = rootPath

  for (const part of directoryParts) {
    currentPath = path.join(currentPath, part)
    directories.push(currentPath)
  }

  return directories
}

function globToRegExp(pattern: string): RegExp {
  let source = ""

  for (let index = 0; index < pattern.length; index += 1) {
    const char = pattern[index]!
    const nextChar = pattern[index + 1]

    if (char === "*") {
      if (nextChar === "*") {
        if (pattern[index + 2] === "/") {
          source += "(?:.*/)?"
          index += 2
        } else {
          source += ".*"
          index += 1
        }
      } else {
        source += "[^/]*"
      }
      continue
    }

    if (char === "?") {
      source += "[^/]"
      continue
    }

    if (char === "\\" && nextChar !== undefined) {
      source += escapeRegExp(nextChar)
      index += 1
      continue
    }

    source += escapeRegExp(char)
  }

  return new RegExp(`^${source}$`)
}

function trimUnescapedTrailingWhitespace(line: string): string {
  let end = line.length
  while (end > 0) {
    const char = line[end - 1]!
    if (char !== " " && char !== "\t") {
      break
    }

    if (isEscaped(line, end - 1)) {
      break
    }

    end -= 1
  }

  return line.slice(0, end)
}

function isEscaped(text: string, index: number): boolean {
  let slashCount = 0
  for (let current = index - 1; current >= 0; current -= 1) {
    if (text[current] !== "\\") {
      break
    }
    slashCount += 1
  }

  return slashCount % 2 === 1
}

function escapeRegExp(value: string): string {
  return value.replace(/[|\\{}()[\]^$+*?.]/g, "\\$&")
}

function toPosix(value: string): string {
  return value.split(path.sep).join("/")
}

function isInsideOrEqual(rootPath: string, targetPath: string): boolean {
  const relativePath = path.relative(rootPath, targetPath)
  return (
    relativePath === "" ||
    (!relativePath.startsWith("..") && !path.isAbsolute(relativePath))
  )
}
