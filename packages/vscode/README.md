# Jonmagic Scripts VS Code Extension

Utilities for my Brain repo, including weekly navigation and wikilink-aware Markdown preview.

## Features

### Brain Sidebar

A dedicated sidebar view for navigating your Brain repository. Access it from the activity bar (book icon).

The sidebar includes:

- **This Week** - Quick access to the current week's note, meeting notes, and daily projects
- **Projects** - Browse folders and Markdown files under `Projects/`

### Week Navigation

Navigate between weeks using the toolbar buttons:

- **←** Previous Week
- **→** Next Week
- **⌂** Go to Current Week
- **↻** Refresh

### Other Commands

- **Brain: Open Recent Brain File** - Quick-open recently edited Brain Markdown files, with git-modified files first
- **Brain: Open Daily Project** - Quick-open recent Daily Project notes from date-prefixed folders
- **Brain: Open Weekly Note** - Quick-open Weekly Notes by week date
- **Brain: Open Project Note** - Quick-open Markdown notes under `Projects/` without opening Explorer
- **Brain: Open Meeting Note** - Quick-open recent Meeting Notes by meeting date
- **Brain: Open Bookmark** - Quick-open recent Brain bookmarks by date
- **Brain: Copy Path Wikilink** - Copy a path-based wikilink for the selected or active Brain Markdown file
- **Brain: Copy UID Wikilink** - Copy a UID wikilink for the selected or active Brain Markdown file; fails if the file has no `uid` frontmatter
- **Brain: Append Weekly Note TODO** - Append a `- [ ]` item under `## TODO` in the current Weekly Note; fails if the weekly note or heading is missing
- **Brain: Add Reference to Project** - Add the selected Brain file or a URL to an existing Project `references.md` under a chosen `##` heading
- **Brain: Rebuild Index** - Rebuild the Brain Markdown, UID, and backlink index used by wikilinks and navigation
- **Brain: Create Daily Project Note** - Create a new numbered project note for a selected date
- **Brain: Add Frontmatter to Current File** - Add YAML frontmatter to the current markdown file
- **Brain: Create Bookmark** - Create a new Brain bookmark from a URL

### Wikilink Preview

The extension teaches VS Code's native Markdown preview to render Brain wikilinks:

- `[[Wiki/Page]]`
- `[[Wiki/Page|Custom Label]]`
- `[[uid:abc123]]`
- `[[uid:abc123|Custom Label]]`

Resolved wikilinks become clickable preview links. Unresolved wikilinks stay visibly unresolved in the preview instead of becoming dead anchors.

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `jonmagic.brainPath` | `~/Brain` | Path to the Brain repository folder. This is the canonical Brain root used by the sidebar, cache, wikilink navigation, and note creation commands. |

## Commands

| Command | Description |
|---------|-------------|
| `Brain: Previous Week` | Navigate to the previous week |
| `Brain: Next Week` | Navigate to the next week |
| `Brain: Go to Current Week` | Jump back to the current week |
| `Brain: Refresh` | Refresh the sidebar content |
| `Brain: Open Recent Brain File` | Quick-open recently edited Brain Markdown files, with git-modified files first |
| `Brain: Open Daily Project` | Quick-open recent Daily Project notes from date-prefixed folders |
| `Brain: Open Weekly Note` | Quick-open Weekly Notes by week date |
| `Brain: Open Project Note` | Quick-open Markdown notes under `Projects/` without opening Explorer |
| `Brain: Open Meeting Note` | Quick-open recent Meeting Notes by meeting date |
| `Brain: Open Bookmark` | Quick-open recent Brain bookmarks by date |
| `Brain: Copy Path Wikilink` | Copy a path-based wikilink for the selected or active Brain Markdown file |
| `Brain: Copy UID Wikilink` | Copy a UID wikilink for the selected or active Brain Markdown file |
| `Brain: Append Weekly Note TODO` | Append a lightweight checkbox TODO to the current Weekly Note |
| `Brain: Add Reference to Project` | Add a selected Brain file or URL to an existing Project `references.md` heading |
| `Brain: Rebuild Index` | Rebuild the Brain Markdown, UID, and backlink index |
| `Brain: Create Daily Project Note` | Create a new daily project note for a selected date |
| `Brain: Add Frontmatter to Current File` | Add frontmatter to current file |
| `Brain: Create Bookmark` | Create a new Brain bookmark from a URL |

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
