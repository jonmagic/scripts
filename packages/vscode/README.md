# Jonmagic Scripts VS Code Extension

Utilities for my Brain repo (Daily Projects, wikilinks, etc.)

## Features

### Brain Sidebar

A dedicated sidebar view for navigating your Brain repository's weekly structure. Access it from the activity bar (book icon).

The sidebar displays:

- **Weekly Note** - Quick access to the current week's note
- **Meeting Notes** - Organized by day with meeting times
- **Daily Projects** - Organized by day

### Week Navigation

Navigate between weeks using the toolbar buttons:

- **←** Previous Week
- **→** Next Week
- **⌂** Go to Current Week
- **↻** Refresh

### Other Commands

- **Jonmagic: Create Daily Project Note** - Create a new numbered project note for today
- **Jonmagic: Add Frontmatter to Current File** - Add YAML frontmatter to the current markdown file

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `jonmagic.brain.path` | `~/Brain` | Path to the Brain repository folder |

## Commands

| Command | Description |
|---------|-------------|
| `Brain: Previous Week` | Navigate to the previous week |
| `Brain: Next Week` | Navigate to the next week |
| `Brain: Go to Current Week` | Jump back to the current week |
| `Brain: Refresh` | Refresh the sidebar content |
| `Jonmagic: Create Daily Project Note` | Create a new daily project note |
| `Jonmagic: Add Frontmatter to Current File` | Add frontmatter to current file |

## Installation

```bash
# From repository root
bin/install-vscode-extension
```

Or build manually:

```bash
cd packages/vscode
bun run build
bun run package
code-insiders --install-extension jonmagic-scripts-0.0.0.vsix
```
