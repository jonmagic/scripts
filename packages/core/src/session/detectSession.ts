// Session detection for agent CLI tools.
//
// Detects which agent tool is running (opencode, copilot, claude) and resolves
// the current session ID by finding the most recently active session.

import * as fs from "node:fs"
import * as path from "node:path"
import * as crypto from "node:crypto"
import * as os from "node:os"

export type AgentTool = "opencode" | "copilot" | "claude"

export interface SessionInfo {
  /** Which CLI tool is running. */
  tool: AgentTool
  /** The session identifier (format varies by tool). */
  sessionId: string
  /** The shell command to resume this session. */
  resume: string
}

/**
 * Detect which agent tool is running based on environment variables.
 * Returns null if no known agent tool is detected.
 */
export function detectTool(): AgentTool | null {
  if (process.env.OPENCODE === "1") return "opencode"
  if (process.env.COPILOT_PROXY_TOKEN_CMD) return "copilot"
  if (process.env.CLAUDE_CODE === "1" || process.env.CLAUDE === "1")
    return "claude"
  return null
}

/**
 * Build the shell command to resume a session.
 */
export function buildResumeCommand(tool: AgentTool, sessionId: string): string {
  switch (tool) {
    case "opencode":
      return `opencode -s ${sessionId}`
    case "copilot":
      return `copilot --resume=${sessionId}`
    case "claude":
      return `claude --resume ${sessionId}`
  }
}

/**
 * Resolve the current OpenCode session ID.
 *
 * OpenCode stores sessions in:
 *   ~/.local/share/opencode/storage/session/<project-hash>/ses_<id>.json
 * where project-hash is SHA-1 of the absolute project directory path.
 *
 * Messages are stored in:
 *   ~/.local/share/opencode/storage/message/ses_<id>/
 *
 * We find the session with the most recently modified message directory.
 */
function resolveOpenCodeSession(projectDir: string): string | null {
  const absDir = path.resolve(projectDir)
  const projectHash = crypto.createHash("sha1").update(absDir).digest("hex")

  const home = os.homedir()
  const sessionDir = path.join(
    home,
    ".local/share/opencode/storage/session",
    projectHash
  )

  if (!fs.existsSync(sessionDir)) return null

  const messageDir = path.join(
    home,
    ".local/share/opencode/storage/message"
  )

  const sessionFiles = fs
    .readdirSync(sessionDir)
    .filter((f) => f.startsWith("ses_") && f.endsWith(".json"))

  if (sessionFiles.length === 0) return null

  let bestSession: string | null = null
  let bestMtime = 0

  for (const file of sessionFiles) {
    const sessionId = file.replace(".json", "")
    const msgDir = path.join(messageDir, sessionId)

    let mtime = 0
    if (fs.existsSync(msgDir)) {
      mtime = fs.statSync(msgDir).mtimeMs
    } else {
      mtime = fs.statSync(path.join(sessionDir, file)).mtimeMs
    }

    if (mtime > bestMtime) {
      bestMtime = mtime
      bestSession = sessionId
    }
  }

  return bestSession
}

/**
 * Resolve the current Copilot session ID.
 *
 * Copilot stores sessions in:
 *   ~/.copilot/session-state/<uuid>/events.jsonl
 *
 * We find the session with the most recently modified events.jsonl.
 */
function resolveCopilotSession(): string | null {
  const home = os.homedir()
  const sessionStateDir = path.join(home, ".copilot/session-state")

  if (!fs.existsSync(sessionStateDir)) return null

  const uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  const entries = fs
    .readdirSync(sessionStateDir)
    .filter((name) => uuidPattern.test(name))

  if (entries.length === 0) return null

  let bestSession: string | null = null
  let bestMtime = 0

  for (const uuid of entries) {
    const eventsFile = path.join(sessionStateDir, uuid, "events.jsonl")
    if (!fs.existsSync(eventsFile)) continue

    const mtime = fs.statSync(eventsFile).mtimeMs
    if (mtime > bestMtime) {
      bestMtime = mtime
      bestSession = uuid
    }
  }

  return bestSession
}

/**
 * Detect the current agent session.
 *
 * @param projectDir - The project directory (used for OpenCode session resolution).
 *                     Defaults to cwd.
 * @returns SessionInfo if a session was detected, null otherwise.
 */
export function detectSession(projectDir?: string): SessionInfo | null {
  const tool = detectTool()
  if (!tool) return null

  const dir = projectDir ?? process.cwd()
  let sessionId: string | null = null

  switch (tool) {
    case "opencode":
      sessionId = resolveOpenCodeSession(dir)
      break
    case "copilot":
      sessionId = resolveCopilotSession()
      break
    case "claude":
      // No known reliable detection mechanism for Claude sessions yet
      return null
  }

  if (!sessionId) return null

  return {
    tool,
    sessionId,
    resume: buildResumeCommand(tool, sessionId),
  }
}
