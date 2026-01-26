/**
 * Skill Manager (sm)
 *
 * Manages skill sources and installs skills into target agent folders.
 *
 * Sources can be:
 * - Local folders (e.g., ~/code/jonmagic/skills)
 * - GitHub repos (public or private)
 *
 * Targets:
 * - Copilot: .github/skills or ~/.copilot/skills
 * - Claude: .claude/skills
 * - Global: ~/.copilot/skills
 *
 * Commands:
 * - sm source add <name> <path|git>
 * - sm source list
 * - sm source remove <name>
 * - sm install <skill> --agent <copilot|claude> --target <project|global>
 * - sm list --installed
 * - sm update <skill>
 * - sm doctor
 */

import * as fs from "node:fs"
import * as path from "node:path"
import * as os from "node:os"

export interface SkillSource {
  name: string
  type: "local" | "git"
  path: string // local path or git URL
}

export interface InstalledSkill {
  name: string
  source: string
  target: string
  installPath: string
  isSymlink: boolean
}

export interface SkillManagerConfig {
  sources: SkillSource[]
  installed: InstalledSkill[]
}

const CONFIG_DIR = process.env.SKILL_MANAGER_CONFIG_DIR || path.join(os.homedir(), ".config", "skill-manager")
const CONFIG_FILE = path.join(CONFIG_DIR, "config.json")

function loadConfig(): SkillManagerConfig {
  if (!fs.existsSync(CONFIG_FILE)) {
    return { sources: [], installed: [] }
  }
  const raw = fs.readFileSync(CONFIG_FILE, "utf-8")
  return JSON.parse(raw) as SkillManagerConfig
}

function saveConfig(config: SkillManagerConfig): void {
  fs.mkdirSync(CONFIG_DIR, { recursive: true })
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), "utf-8")
}

function expandPath(p: string): string {
  if (p.startsWith("~/")) {
    return path.join(os.homedir(), p.slice(2))
  }
  return path.resolve(p)
}

function getTargetDir(agent: string, target: string, projectDir?: string): string {
  if (target === "global") {
    if (agent === "copilot") {
      return path.join(os.homedir(), ".copilot", "skills")
    } else if (agent === "claude") {
      return path.join(os.homedir(), ".claude", "skills")
    }
  } else if (target === "project") {
    const base = projectDir || process.cwd()
    if (agent === "copilot") {
      return path.join(base, ".github", "skills")
    } else if (agent === "claude") {
      return path.join(base, ".claude", "skills")
    }
  }
  throw new Error(`Unknown agent '${agent}' or target '${target}'`)
}

function findSkillInSources(skillName: string, config: SkillManagerConfig): { source: SkillSource; skillPath: string } | null {
  for (const source of config.sources) {
    if (source.type === "local") {
      const expanded = expandPath(source.path)
      // Check skills/ subdirectory first (common pattern)
      const skillsSubdir = path.join(expanded, "skills", skillName)
      if (fs.existsSync(skillsSubdir) && fs.existsSync(path.join(skillsSubdir, "SKILL.md"))) {
        return { source, skillPath: skillsSubdir }
      }
      // Check direct path
      const direct = path.join(expanded, skillName)
      if (fs.existsSync(direct) && fs.existsSync(path.join(direct, "SKILL.md"))) {
        return { source, skillPath: direct }
      }
    }
    // Git sources would need cloning - not implemented yet
  }
  return null
}

function listAvailableSkills(config: SkillManagerConfig): { source: string; name: string; description: string }[] {
  const skills: { source: string; name: string; description: string }[] = []

  for (const source of config.sources) {
    if (source.type === "local") {
      const expanded = expandPath(source.path)
      const dirs = [expanded, path.join(expanded, "skills")]

      for (const dir of dirs) {
        if (!fs.existsSync(dir)) continue

        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          if (!entry.isDirectory() || entry.name.startsWith(".")) continue

          const skillMd = path.join(dir, entry.name, "SKILL.md")
          if (!fs.existsSync(skillMd)) continue

          // Extract description from frontmatter
          const content = fs.readFileSync(skillMd, "utf-8")
          const descMatch = content.match(/^description:\s*(.+)$/m)
          const description = descMatch?.[1]?.trim() ?? ""

          skills.push({
            source: source.name,
            name: entry.name,
            description: description.slice(0, 80) + (description.length > 80 ? "..." : ""),
          })
        }
      }
    }
  }

  return skills
}

// Commands

export function sourceAdd(name: string, sourcePath: string): void {
  const config = loadConfig()

  // Check if source already exists
  if (config.sources.some((s) => s.name === name)) {
    console.error(`Source '${name}' already exists`)
    process.exit(1)
  }

  // Determine if local or git
  const isGit = sourcePath.startsWith("git@") || sourcePath.startsWith("https://") || sourcePath.includes("github.com")
  const type: "local" | "git" = isGit ? "git" : "local"

  if (type === "local") {
    const expanded = expandPath(sourcePath)
    if (!fs.existsSync(expanded)) {
      console.error(`Path does not exist: ${expanded}`)
      process.exit(1)
    }
  }

  config.sources.push({ name, type, path: sourcePath })
  saveConfig(config)
  console.log(`Added source '${name}' (${type}): ${sourcePath}`)
}

export function sourceList(): void {
  const config = loadConfig()

  if (config.sources.length === 0) {
    console.log("No sources configured.")
    console.log("\nAdd a source with:")
    console.log("  sm source add <name> <path>")
    return
  }

  console.log("Configured sources:\n")
  for (const source of config.sources) {
    const expanded = source.type === "local" ? expandPath(source.path) : source.path
    const exists = source.type === "local" ? fs.existsSync(expanded) : "?"
    const status = exists === true ? "✓" : exists === false ? "✗ (missing)" : ""
    console.log(`  ${source.name} (${source.type})`)
    console.log(`    ${expanded} ${status}`)
  }
}

export function sourceRemove(name: string): void {
  const config = loadConfig()
  const idx = config.sources.findIndex((s) => s.name === name)

  if (idx === -1) {
    console.error(`Source '${name}' not found`)
    process.exit(1)
  }

  config.sources.splice(idx, 1)
  saveConfig(config)
  console.log(`Removed source '${name}'`)
}

export function install(skillName: string, agent: string, target: string, projectDir?: string): void {
  const config = loadConfig()

  // Find skill in sources
  const found = findSkillInSources(skillName, config)
  if (!found) {
    console.error(`Skill '${skillName}' not found in any source`)
    console.log("\nAvailable skills:")
    const available = listAvailableSkills(config)
    for (const s of available) {
      console.log(`  ${s.name} (${s.source})`)
    }
    process.exit(1)
  }

  const targetDir = getTargetDir(agent, target, projectDir)
  const installPath = path.join(targetDir, skillName)

  // Check if already installed
  if (fs.existsSync(installPath)) {
    const stat = fs.lstatSync(installPath)
    if (stat.isSymbolicLink()) {
      const linkTarget = fs.readlinkSync(installPath)
      if (linkTarget === found.skillPath) {
        console.log(`Skill '${skillName}' already installed (symlink to ${linkTarget})`)
        return
      }
      console.log(`Updating symlink for '${skillName}'`)
      fs.unlinkSync(installPath)
    } else {
      console.error(`Path already exists and is not a symlink: ${installPath}`)
      process.exit(1)
    }
  }

  // Create symlink (for local sources)
  fs.mkdirSync(targetDir, { recursive: true })
  fs.symlinkSync(found.skillPath, installPath)

  // Record installation
  const installed: InstalledSkill = {
    name: skillName,
    source: found.source.name,
    target: `${agent}:${target}`,
    installPath,
    isSymlink: true,
  }

  // Remove any existing record for this skill/target combo
  config.installed = config.installed.filter(
    (i) => !(i.name === skillName && i.target === installed.target)
  )
  config.installed.push(installed)
  saveConfig(config)

  console.log(`Installed '${skillName}' to ${installPath}`)
  console.log(`  Source: ${found.source.name} (${found.skillPath})`)
}

export function listInstalled(): void {
  const config = loadConfig()

  if (config.installed.length === 0) {
    console.log("No skills installed via skill-manager.")
    return
  }

  console.log("Installed skills:\n")
  for (const skill of config.installed) {
    const exists = fs.existsSync(skill.installPath)
    const status = exists ? "✓" : "✗ (missing)"

    let linkStatus = ""
    if (exists && skill.isSymlink) {
      try {
        const linkTarget = fs.readlinkSync(skill.installPath)
        const linkOk = fs.existsSync(linkTarget)
        linkStatus = linkOk ? "" : " (broken link)"
      } catch {
        linkStatus = " (not a symlink)"
      }
    }

    console.log(`  ${skill.name} ${status}${linkStatus}`)
    console.log(`    Target: ${skill.target}`)
    console.log(`    Path:   ${skill.installPath}`)
    console.log(`    Source: ${skill.source}`)
  }
}

export function listAvailable(): void {
  const config = loadConfig()
  const skills = listAvailableSkills(config)

  if (skills.length === 0) {
    console.log("No skills found in sources.")
    console.log("\nAdd a source with:")
    console.log("  sm source add <name> <path>")
    return
  }

  console.log("Available skills:\n")

  // Group by source
  const bySource: Record<string, typeof skills> = {}
  for (const s of skills) {
    if (!bySource[s.source]) bySource[s.source] = []
    bySource[s.source]!.push(s)
  }

  for (const [source, sourceSkills] of Object.entries(bySource)) {
    console.log(`  [${source}]`)
    for (const s of sourceSkills) {
      const desc = s.description ? ` — ${s.description}` : ""
      console.log(`    ${s.name}${desc}`)
    }
    console.log()
  }
}

export function doctor(): void {
  const config = loadConfig()
  let issues = 0

  console.log("Checking skill-manager configuration...\n")

  // Check sources
  console.log("Sources:")
  for (const source of config.sources) {
    if (source.type === "local") {
      const expanded = expandPath(source.path)
      if (!fs.existsSync(expanded)) {
        console.log(`  ✗ ${source.name}: path does not exist (${expanded})`)
        issues++
      } else {
        console.log(`  ✓ ${source.name}: ${expanded}`)
      }
    } else {
      console.log(`  ? ${source.name}: git source (not checked)`)
    }
  }

  // Check installed skills
  console.log("\nInstalled skills:")
  for (const skill of config.installed) {
    if (!fs.existsSync(skill.installPath)) {
      console.log(`  ✗ ${skill.name}: install path missing (${skill.installPath})`)
      issues++
      continue
    }

    if (skill.isSymlink) {
      try {
        const linkTarget = fs.readlinkSync(skill.installPath)
        if (!fs.existsSync(linkTarget)) {
          console.log(`  ✗ ${skill.name}: broken symlink → ${linkTarget}`)
          issues++
        } else {
          console.log(`  ✓ ${skill.name}: ${skill.installPath} → ${linkTarget}`)
        }
      } catch {
        console.log(`  ✗ ${skill.name}: expected symlink but is regular directory`)
        issues++
      }
    } else {
      console.log(`  ✓ ${skill.name}: ${skill.installPath} (copied)`)
    }
  }

  console.log()
  if (issues === 0) {
    console.log("No issues found.")
  } else {
    console.log(`Found ${issues} issue(s).`)
  }
}

export function uninstall(skillName: string, agent?: string, target?: string): void {
  const config = loadConfig()

  // Find matching installations
  let matches = config.installed.filter((i) => i.name === skillName)

  if (agent && target) {
    matches = matches.filter((i) => i.target === `${agent}:${target}`)
  }

  if (matches.length === 0) {
    console.error(`Skill '${skillName}' is not installed`)
    if (agent && target) {
      console.error(`(checked for ${agent}:${target})`)
    }
    process.exit(1)
  }

  if (matches.length > 1 && !agent) {
    console.error(`Skill '${skillName}' is installed in multiple locations:`)
    for (const m of matches) {
      console.error(`  - ${m.target}: ${m.installPath}`)
    }
    console.error("\nSpecify --agent and --target to uninstall a specific one.")
    process.exit(1)
  }

  for (const match of matches) {
    if (fs.existsSync(match.installPath)) {
      const stat = fs.lstatSync(match.installPath)
      if (stat.isSymbolicLink()) {
        fs.unlinkSync(match.installPath)
      } else {
        fs.rmSync(match.installPath, { recursive: true })
      }
      console.log(`Removed: ${match.installPath}`)
    }

    config.installed = config.installed.filter((i) => i !== match)
  }

  saveConfig(config)
  console.log(`Uninstalled '${skillName}'`)
}
