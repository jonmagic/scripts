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
| `weekly-focus-app` | Build and open the native full-screen Weekly Focus app, backed by the GitHub Projects task board | swift |

## Native Weekly Focus App

`weekly-focus-app` opens a native macOS app that shows at most five open tasks,
fills the current monitor by default, and gives each row one action: a bare
Copilot session ID is copied to the clipboard; otherwise the first URL or Brain
wikilink opens; otherwise a new cmux workspace opens in `~/Brain` with `c`
started on that task. Click an item, press `1`-`5`, or press `⌘1`-`⌘5` to run
that action. Hover a row to show its completion checkbox, or command-click the
row, to check it off. Press `⌘O` to open the source weekly note in VS Code
Insiders. Up to five items after the top five fade below the main focus area.
Type in the empty field and press Return to add a task. Press `R` to refresh
and `Q`, `Esc`, or `⌘Q` to quit.

### Task source

Tasks come from a private GitHub Projects V2 board, which is the canonical
store. The app talks to the Projects REST API directly over `URLSession`; it
does not shell out to `gh`. The five focus slots are ordered by the board's
`Focus` field, and unranked items follow in board order. Completing a task sets
`Status` to `Done` and stamps `Reviewed`.

The weekly note remains a fallback. When no credential is available or the
board has never been fetched, the app reads the current week's `## TODO`
section exactly as before, so it still works offline. If the current week file
has not been created yet, it falls back to the latest existing weekly note
instead of failing on Sunday morning.

Reads are served from a local cache at `~/.cache/weekly-focus/board.json` so the
window paints immediately, then a background refresh reconciles it. A live board
read costs roughly 550-700ms and no request to `api.github.com` beats about
320ms from a laptop, so caching is what makes the app usable on a hotkey.
Refreshes send `If-None-Match`, so an unchanged board costs a cheap `304`. The
board is shared state that other tools write to, so an open window also refreshes
every 60 seconds rather than drifting until the next launch.

### Credentials

The token is resolved lazily, off the paint path, in this order:

1. `BRAIN_GITHUB_TOKEN` or `GITHUB_TOKEN`
2. the macOS Keychain, service `com.jonmagic.brainos.github`, account
   `github-token` -- the same entry BrainOS uses, so the two share one credential
3. a one-time bootstrap from `gh auth token`, which is then written to the Keychain

macOS ties a Keychain ACL to the caller's code signature, so an ad-hoc signature
-- whose hash changes on every build -- would re-prompt after every rebuild.
`bin/build-weekly-focus-app` therefore signs the bundle with the first
`Developer ID Application` identity it finds (override with
`WEEKLY_FOCUS_SIGN_IDENTITY`, falls back to ad-hoc when none exists). That gives
a stable designated requirement, so answering **Always Allow** once survives
later rebuilds. The prompt appears during the background refresh rather than at
launch, so the window still paints instantly from cache.

Point the app at a different board with `WEEKLY_FOCUS_PROJECT_OWNER`,
`WEEKLY_FOCUS_PROJECT_NUMBER`, and `WEEKLY_FOCUS_PROJECT_NODE_ID`. Set
`WEEKLY_FOCUS_TIMING=1` to print a startup and refresh timing breakdown to
stderr, which distinguishes a slow Keychain authorization from a slow network.

```bash
bin/weekly-focus-app
bin/weekly-focus-app --print-focus   # prints the card; exits 2 if state is stale
```

The build script installs the Dock-safe app bundle at
`~/Applications/Weekly Focus.app` with the bundled app icon from
`packages/focus-app/Resources/WeeklyFocus.icns`.

The native app has a self-test that creates a temporary Brain, opens a TODO,
checks `⌘1` while the text field is focused, verifies automatic refresh after
an external markdown edit, checks input-field copy/paste and `⌘Q`, adds a TODO,
marks a TODO done, and asks cmux to open a harmless workspace command. It runs
against markdown only so it never writes throwaway items to the real board:

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
