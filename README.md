# Scripts

A TypeScript monorepo for personal automation tools, VS Code extensions, and Raycast extensions.

> **Note:** Looking for the legacy Ruby scripts? See the [v1.0.0 tag](https://github.com/jonmagic/scripts/tree/v1.0.0).

## Packages

| Package | Description |
|---------|-------------|
| `@jonmagic/scripts-core` | Shared utilities and libraries |
| `@jonmagic/scripts-cli` | CLI tools (archive-meeting, etc.) |
| `jonmagic-scripts` | VS Code extension |
| `jonmagic-scripts-raycast` | Raycast extension |

## Quick Start

```bash
# Clone and setup
git clone https://github.com/jonmagic/scripts.git
cd scripts
bin/setup
```

The setup script will:
1. Install Bun (if not already installed)
2. Install dependencies
3. Build all packages

## Development

```bash
# Install dependencies
bun install

# Build all packages
bun run build

# Run tests
bun test

# Lint
bun run lint

# Type check
bun run typecheck
```

## Installing Extensions

### VS Code

```bash
bin/install-vscode-extension
```

### Raycast

```bash
bin/install-raycast-extension
```

## CLI Tools

After running `bin/setup`, add the CLI to your PATH:

```bash
export PATH="$HOME/code/jonmagic/scripts/bin:$PATH"
```

### Requirements

- [Bun](https://bun.sh) - JavaScript runtime (installed by setup)
- [gh](https://cli.github.com) - GitHub CLI
- [copilot](https://githubnext.com/projects/copilot-cli) - GitHub Copilot CLI
- [llm](https://llm.datasette.io/) - Prompt runner for single-shot model calls
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder (for interactive selection)

### Available Commands

| Command | Description | Requirements |
|---------|-------------|--------------|
| `archive-meeting` | Archive a meeting transcript with AI-generated summaries | bun, llm |
| `capture-weekly-note` | Append a rough commitment capture with optional source under `## Captured` in the current weekly note | bun |
| `list-recent-meetings` | List recent Zoom and Teams meeting inputs as JSON | bun |
| `fetch-github-conversation` | Fetch GitHub issue, PR, or discussion as JSON | gh |
| `prepare-pull-request` | Generate PR title/body with Copilot CLI and create PR | git, gh, copilot |
| `weekly-focus` | Print a low-noise Now/Next/Waiting/Captured view from the current weekly note | bun |
| `weekly-focus-card` | Print a sparse focus card capped at five current weekly-note TODOs | bun |
| `weekly-focus-app` | Build and open the native full-screen Weekly Focus app | swift |

## Native Weekly Focus App

`weekly-focus-app` opens a native macOS app that reads the current weekly note,
fills the current monitor by default, and shows at most five unchecked `## TODO`
items. Click an item, press `1`-`5`, or press `⌘1`-`⌘5` to briefly highlight
the row, open a new cmux workspace in `~/Brain`, and bring cmux forward with
`c` started on that TODO. Command-click an item to mark it complete in the
weekly note. Links inside TODO text open directly when clicked. Press `⌘O` to
open the source weekly note in VS Code Insiders. The app also watches the
weekly note and refreshes automatically when an external markdown edit checks
off or adds TODOs. Items after the top five fade below the main focus area.
Type in the empty field and press Return to add a new TODO. Press `R` to
refresh and `Q`, `Esc`, or `⌘Q` to quit.

Weekly Focus reads the current week's note when it exists. If the current week
file has not been created yet, it falls back to the latest existing weekly note
instead of failing on Sunday morning.

```bash
bin/weekly-focus-app
```

The build script installs the Dock-safe app bundle at
`~/Applications/Weekly Focus.app`.

The native app has a self-test that creates a temporary Brain, opens a TODO,
checks `⌘1` while the text field is focused, verifies automatic refresh after
an external markdown edit, checks `⌘Q`, adds a TODO, marks a TODO done, and
asks cmux to open a harmless workspace command:

```bash
bin/test-weekly-focus-app
```

## Raycast Commands

The Raycast extension includes quick Brain actions for the same weekly-note workflow:

| Command | Description |
|---------|-------------|
| `Create Daily Project Note` | Create a numbered Daily Project note |
| `Capture Weekly Note` | Capture a rough commitment with optional source under `## Captured` |
| `Weekly Focus` | Open the native full-screen Weekly Focus app |

## License

ISC
