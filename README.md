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
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder (for interactive selection)

### Available Commands

| Command | Description | Requirements |
|---------|-------------|--------------|
| `archive-meeting` | Archive a meeting transcript with AI-generated summaries | bun, copilot |
| `list-recent-meetings` | List recent Zoom and Teams meeting inputs as JSON | bun |
| `fetch-github-conversation` | Fetch GitHub issue, PR, or discussion as JSON | gh |
| `prepare-pull-request` | Generate PR title/body with Copilot CLI and create PR | git, gh, copilot |

## License

ISC
