/**
 * skill-manager CLI entrypoint
 */

import { parseArgs } from "node:util"
import {
  sourceAdd,
  sourceList,
  sourceRemove,
  install,
  uninstall,
  listInstalled,
  listAvailable,
  doctor,
} from "./skill-manager.js"

const args = process.argv.slice(2)
const command = args[0]
const subcommand = args[1]

function showHelp(): void {
  console.log(`
skill-manager (sm) - Manage skill sources and installations

Usage:
  sm source add <name> <path|git>    Add a skill source
  sm source list                     List configured sources  
  sm source remove <name>            Remove a source
  sm install <skill> [options]       Install a skill
  sm uninstall <skill> [options]     Uninstall a skill
  sm list                            List available skills from sources
  sm list --installed                List installed skills
  sm doctor                          Check for configuration issues

Install options:
  --agent <copilot|claude>           Target agent (default: copilot)
  --target <project|global>          Install location (default: global)
  --project-dir <path>               Project directory for project installs

Examples:
  sm source add jonmagic ~/code/jonmagic/skills
  sm source list
  sm install executive-summary --agent copilot --target global
  sm list --installed
  sm doctor
`)
}

if (!command || command === "--help" || command === "-h") {
  showHelp()
  process.exit(0)
}

// Handle source commands
if (command === "source") {
  if (subcommand === "add") {
    const name = args[2]
    const sourcePath = args[3]
    if (!name || !sourcePath) {
      console.error("Usage: sm source add <name> <path|git>")
      process.exit(1)
    }
    sourceAdd(name, sourcePath)
  } else if (subcommand === "list" || !subcommand) {
    sourceList()
  } else if (subcommand === "remove" || subcommand === "rm") {
    const name = args[2]
    if (!name) {
      console.error("Usage: sm source remove <name>")
      process.exit(1)
    }
    sourceRemove(name)
  } else {
    console.error(`Unknown source command: ${subcommand}`)
    process.exit(1)
  }
  process.exit(0)
}

// Handle install command
if (command === "install") {
  const { values, positionals } = parseArgs({
    args: args.slice(1),
    options: {
      agent: { type: "string", default: "copilot" },
      target: { type: "string", default: "global" },
      "project-dir": { type: "string" },
    },
    allowPositionals: true,
  })

  const skillName = positionals[0]
  if (!skillName) {
    console.error("Usage: sm install <skill> [--agent copilot|claude] [--target project|global]")
    process.exit(1)
  }

  install(skillName, values.agent!, values.target!, values["project-dir"])
  process.exit(0)
}

// Handle uninstall command
if (command === "uninstall" || command === "remove" || command === "rm") {
  const { values, positionals } = parseArgs({
    args: args.slice(1),
    options: {
      agent: { type: "string" },
      target: { type: "string" },
    },
    allowPositionals: true,
  })

  const skillName = positionals[0]
  if (!skillName) {
    console.error("Usage: sm uninstall <skill> [--agent copilot|claude] [--target project|global]")
    process.exit(1)
  }

  uninstall(skillName, values.agent, values.target)
  process.exit(0)
}

// Handle list command
if (command === "list" || command === "ls") {
  const { values } = parseArgs({
    args: args.slice(1),
    options: {
      installed: { type: "boolean", default: false },
    },
    allowPositionals: true,
  })

  if (values.installed) {
    listInstalled()
  } else {
    listAvailable()
  }
  process.exit(0)
}

// Handle doctor command
if (command === "doctor") {
  doctor()
  process.exit(0)
}

console.error(`Unknown command: ${command}`)
console.error("Run 'sm --help' for usage")
process.exit(1)
