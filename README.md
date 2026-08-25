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
| `archive-meeting` | Archive a meeting transcript with AI-generated summaries, then review the tasks it found for you | bun, llm |
| `capture-weekly-note` | Add a task to the Brain Tasks board for the current week, with an optional source | bun |
| `list-recent-meetings` | List recent Zoom and Teams meeting inputs as JSON | bun |
| `fetch-github-conversation` | Fetch GitHub issue, PR, or discussion as JSON | gh |
| `weekly-focus` | Print a low-noise Now/Next/Waiting view from the Brain Tasks board | bun |
| `weekly-focus-card` | Print a sparse focus card capped at five open board tasks | bun |
| `weekly-focus-app` | Build and open the native full-screen Weekly Focus app, backed by the GitHub Projects task board | swift |

`archive-meeting` opens its generated task candidates in `$VISUAL`, then `$EDITOR`. When neither is configured, it uses VS Code Insiders with `--wait` when available and otherwise falls back to `vi`.

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

A private GitHub Projects V2 board is the only task source. The app talks to
the Projects REST API directly over `URLSession`; it does not shell out to `gh`.
The five focus slots are ordered by the board's `Focus` field, and unranked
items follow in board order. Completing a task sets `Status` to `Done` and
stamps `Reviewed`.

The fetch asks for everything that is not `Done` or `Dropped`, which is the same
rule the app applies client-side. It deliberately does not filter by the board's
`Week` field: doing that left the app blank whenever the weekly roll had not run
yet, and hid captured tasks that arrived without a week. Excluding the closed
statuses is also what keeps the payload flat, since open work stays roughly
constant while `Done` accumulates.

There is no markdown fallback. Weekly notes are still used for wikilink
resolution and for `⌘O`, but they no longer hold tasks, so reading and writing
cannot disagree about which store is canonical.

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
`WEEKLY_FOCUS_PROJECT_NUMBER`, and `WEEKLY_FOCUS_PROJECT_NODE_ID`, and at a
different API root with `WEEKLY_FOCUS_API_BASE`. `WEEKLY_FOCUS_CACHE` moves the
cache file and `WEEKLY_FOCUS_REFRESH_SECONDS` changes the open-window refresh
interval; both exist so the end-to-end test can run without touching real state.
Set `WEEKLY_FOCUS_TIMING=1` to print a startup and refresh timing breakdown to
stderr, which distinguishes a slow Keychain authorization from a slow network.

```bash
bin/weekly-focus-app
bin/weekly-focus-app --print-focus   # prints the card; exits 2 if state is stale
```

The build script installs the Dock-safe app bundle at
`~/Applications/Weekly Focus.app` with the bundled app icon from
`packages/focus-app/Resources/WeeklyFocus.icns`.

The native app has an end-to-end test that stands up a local stub of the
Projects API (`packages/focus-app/Tools/stub-projects-api.py`) and points the
app at it, so it never reads or writes the real board. It captures a task,
completes one, checks `⌘1` while the text field is focused, verifies the open
window picks up a change made to the board elsewhere, checks input-field
copy/paste and `⌘Q`, and asks cmux to open a harmless workspace command:

```bash
bin/test-weekly-focus-app
```

## Raycast Commands

The Raycast extension includes quick Brain actions for the same weekly-note workflow:

| Command | Description |
|---------|-------------|
| `Create Daily Project Note` | Create a numbered Daily Project note |
| `Capture Weekly Note` | Add a task to the Brain Tasks board with an optional source |
| `Weekly Focus` | Open the native full-screen Weekly Focus app |

## License

ISC
