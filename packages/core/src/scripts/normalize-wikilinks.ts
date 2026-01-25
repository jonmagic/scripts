#!/usr/bin/env node
// Normalize all wikilinks in a Brain repository to use full paths.
//
// Transforms:
// 1. [[uid:xxx|Some/Path]] → [[Full/Path/To/File]] (resolves UID to actual path)
// 2. [[just-filename]] → [[Full/Path/To/just-filename]] (if unambiguous)
// 3. [[Full/Path]] → unchanged
//
// Usage:
//   npx tsx normalize-wikilinks.ts /path/to/brain --dry-run
//   npx tsx normalize-wikilinks.ts /path/to/brain

import * as fs from "node:fs"
import * as path from "node:path"
import { extractWikilinks, pathToDisplayPath, UID_PREFIX, buildUidIndex, type UidIndex, type FileInfo } from "../wikilinks/index.js"
import { extractUid } from "../frontmatter/index.js"

interface LinkChange {
  file: string
  line: number
  oldLink: string
  newLink: string
}

interface NormalizeResult {
  changes: LinkChange[]
  filesScanned: number
  filesModified: number
}

// Directories to scan for markdown files
const CONTENT_DIRS = [
  "Daily Projects",
  "Executive Summaries",
  "Meeting Notes",
  "Projects",
  "Snippets",
  "Transcripts",
  "Weekly Notes",
]

/**
 * Find all markdown files in the brain repository.
 */
function findMarkdownFiles(brainRoot: string): string[] {
  const files: string[] = []

  for (const dir of CONTENT_DIRS) {
    const dirPath = path.join(brainRoot, dir)
    if (!fs.existsSync(dirPath)) continue

    const walkDir = (currentPath: string) => {
      const entries = fs.readdirSync(currentPath, { withFileTypes: true })
      for (const entry of entries) {
        const fullPath = path.join(currentPath, entry.name)
        if (entry.isDirectory()) {
          walkDir(fullPath)
        } else if (entry.isFile() && entry.name.endsWith(".md")) {
          files.push(fullPath)
        }
      }
    }

    walkDir(dirPath)
  }

  return files
}

/**
 * Build an index of filename (lowercase) → full relative paths.
 * Used to resolve short refs to full paths.
 */
function buildFilenameIndex(
  brainRoot: string,
  files: string[]
): Map<string, string[]> {
  const index = new Map<string, string[]>()

  for (const file of files) {
    const relativePath = path.relative(brainRoot, file)
    const displayPath = pathToDisplayPath(relativePath)
    const filename = path.basename(displayPath).toLowerCase()

    const existing = index.get(filename) || []
    existing.push(displayPath)
    index.set(filename, existing)
  }

  return index
}

/**
 * Build a UID index from all files to resolve uid:xxx references.
 */
function buildUidIndexFromFiles(brainRoot: string, files: string[]): UidIndex {
  const fileInfos: FileInfo[] = []
  
  for (const file of files) {
    const relativePath = path.relative(brainRoot, file)
    const content = fs.readFileSync(file, "utf-8")
    fileInfos.push({ relativePath, content })
  }
  
  return buildUidIndex(fileInfos)
}

/**
 * Normalize wikilinks in a single file.
 */
function normalizeFileLinks(
  brainRoot: string,
  filePath: string,
  filenameIndex: Map<string, string[]>,
  uidIndex: UidIndex,
  dryRun: boolean
): LinkChange[] {
  const changes: LinkChange[] = []
  let content = fs.readFileSync(filePath, "utf-8")
  const relativePath = path.relative(brainRoot, filePath)

  const links = extractWikilinks(content)

  for (const link of links) {
    let newTarget: string | null = null

    // Case 1: uid:xxx|label format → resolve UID to actual path
    if (link.target.startsWith(UID_PREFIX)) {
      const uid = link.target.slice(UID_PREFIX.length)
      const resolvedPath = uidIndex.byUid.get(uid)
      
      if (resolvedPath) {
        // Convert to display path (without .md)
        newTarget = pathToDisplayPath(resolvedPath)
      } else if (link.label) {
        // UID not found, try to resolve the label as a short ref
        const labelLower = link.label.toLowerCase()
        const matches = filenameIndex.get(labelLower)
        if (matches && matches.length === 1) {
          newTarget = matches[0]
        } else {
          console.warn(
            `  Warning: UID "${uid}" not found and label "${link.label}" is ambiguous in ${relativePath}`
          )
        }
      }
    }
    // Case 2: Short ref (just filename, no /) → resolve to full path
    else if (!link.target.includes("/")) {
      const filename = link.target.toLowerCase()
      const matches = filenameIndex.get(filename)

      if (matches && matches.length === 1) {
        // Unambiguous match
        newTarget = matches[0]
      } else if (matches && matches.length > 1) {
        // Ambiguous - log warning but don't change
        console.warn(
          `  Warning: Ambiguous short ref "${link.target}" in ${relativePath} ` +
            `(matches: ${matches.join(", ")})`
        )
      }
    }
    // Case 3: Already has path - check if it needs .md removed or other normalization
    // For now, leave as-is

    if (newTarget && newTarget !== link.target) {
      const newLink = `[[${newTarget}]]`

      // Find line number for reporting
      const beforeMatch = content.slice(0, content.indexOf(link.full))
      const lineNum = (beforeMatch.match(/\n/g) || []).length + 1

      changes.push({
        file: relativePath,
        line: lineNum,
        oldLink: link.full,
        newLink,
      })

      if (!dryRun) {
        content = content.replace(link.full, newLink)
      }
    }
  }

  if (!dryRun && changes.length > 0) {
    fs.writeFileSync(filePath, content, "utf-8")
  }

  return changes
}

/**
 * Normalize all wikilinks in a Brain repository.
 */
export function normalizeWikilinks(
  brainRoot: string,
  dryRun: boolean = true
): NormalizeResult {
  console.log(`Scanning ${brainRoot}...`)
  console.log(`Mode: ${dryRun ? "DRY RUN" : "APPLY CHANGES"}`)
  console.log()

  const files = findMarkdownFiles(brainRoot)
  console.log(`Found ${files.length} markdown files`)

  const filenameIndex = buildFilenameIndex(brainRoot, files)
  console.log(`Built filename index with ${filenameIndex.size} unique filenames`)
  
  const uidIndex = buildUidIndexFromFiles(brainRoot, files)
  console.log(`Built UID index with ${uidIndex.byUid.size} UIDs`)
  console.log()

  const allChanges: LinkChange[] = []
  const modifiedFiles = new Set<string>()

  for (const file of files) {
    const changes = normalizeFileLinks(brainRoot, file, filenameIndex, uidIndex, dryRun)
    if (changes.length > 0) {
      allChanges.push(...changes)
      modifiedFiles.add(file)
    }
  }

  // Print summary
  console.log()
  console.log("=".repeat(60))
  console.log(`${dryRun ? "[DRY RUN] " : ""}Summary:`)
  console.log(`  Files scanned: ${files.length}`)
  console.log(`  Files ${dryRun ? "would be " : ""}modified: ${modifiedFiles.size}`)
  console.log(`  Links ${dryRun ? "would be " : ""}changed: ${allChanges.length}`)

  if (allChanges.length > 0 && allChanges.length <= 50) {
    console.log()
    console.log("Changes:")
    for (const change of allChanges) {
      console.log(`  ${change.file}:${change.line}`)
      console.log(`    ${change.oldLink} → ${change.newLink}`)
    }
  } else if (allChanges.length > 50) {
    console.log()
    console.log(`First 20 changes:`)
    for (const change of allChanges.slice(0, 20)) {
      console.log(`  ${change.file}:${change.line}`)
      console.log(`    ${change.oldLink} → ${change.newLink}`)
    }
    console.log(`  ... and ${allChanges.length - 20} more`)
  }

  return {
    changes: allChanges,
    filesScanned: files.length,
    filesModified: modifiedFiles.size,
  }
}

// CLI interface
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2)

  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    console.log(`Usage: normalize-wikilinks.ts <brain-path> [--dry-run]

Normalize all wikilinks to use full paths.

Arguments:
  brain-path    Path to the Brain repository root

Options:
  --dry-run     Preview changes without modifying files
  -h, --help    Show this help message

Examples:
  npx tsx normalize-wikilinks.ts ~/Brain --dry-run
  npx tsx normalize-wikilinks.ts ~/Brain`)
    process.exit(0)
  }

  const brainPath = args[0]
  const dryRun = args.includes("--dry-run")

  if (!brainPath || !fs.existsSync(brainPath)) {
    console.error(`Error: Brain path not found: ${brainPath}`)
    process.exit(1)
  }

  normalizeWikilinks(brainPath, dryRun)
}
