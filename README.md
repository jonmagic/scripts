# scripts

The scripts that reduce friction so I can move from task to task faster.


## Setup

Before using the scripts in this repo, run the bootstrap script to ensure required dependencies (like Homebrew and fzf) are installed:

```sh
bin/bootstrap
```

This script will automatically install Homebrew (if needed) and fzf, so you don't have to do it manually.

## Instructions

This repo uses the terms **porcelain** and **plumbing** to describe its scripts, similar to how git distinguishes between user-facing and lower-level commands:

- **Porcelain**: User-friendly scripts intended for direct use.
- **Plumbing**: Lower-level scripts intended to be used by other scripts or for advanced workflows.

### Porcelain Commands

#### Create Weekly Note (`bin/create-weekly-note`)

This script helps you quickly create a new weekly note from a template and place it in your notes directory.

**Usage:**

```sh
/path/to/scripts/bin/create-weekly-note --template-path /path/to/weekly/notes/template.md --target-dir /path/to/weekly/notes
```

### Plumbing Commands

#### Select Folder (`bin/select-folder`)

This script takes a target directory as an argument and returns the 10 names of the most recently updated folders in that directory. It then lets you select a folder using arrow keys or fuzzy search (via `fzf`) and returns the full path of the selected folder.

**Usage:**

```sh
/path/to/scripts/bin/select-folder --target-dir /path/to/target
```
