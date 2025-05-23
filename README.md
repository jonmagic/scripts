# scripts

I organize my life with markdown and these scripts help me work quickly and seamlessly.

One weekly note sets the plan, and conversations, captured as transcripts, are archived, summarized with AI, and linked to long-running notes by person or group. These scripts reduce friction at every step: from capturing insights to surfacing them when needed.

I organize my notes to map to my processes:

```
Notes/
├── Weekly Notes/  # One file per week, e.g. "Week of 2024-05-19.md"
├── Meeting Notes/  # One file per person or group, contents by date descending
├── Transcripts/YYYY-MM-DD/  # Raw transcripts, incrementally numbered
├── Executive Summaries/YYYY-MM-DD/  # LLM summaries for each transcript
├── ...
```

This structure supports a semantically searchable, AI-augmented note system, fast to navigate, easy to sync, and version-control friendly.

## Setup

Before using the scripts in this repo, run the bootstrap script to ensure required dependencies (like Homebrew, fzf, and llm) are installed:

```sh
bin/bootstrap
```

## Instructions

This repo uses the terms **porcelain** and **plumbing** to describe its scripts, similar to how git distinguishes between user-facing and lower-level commands:

- **Porcelain**: User-friendly scripts intended for direct use.
  - [Archive Meeting](#archive-meeting)
  - [Create Weekly Note](#create-weekly-note)
  - [Fetch GitHub Conversation](#fetch-github-conversation)
  - [Prepare Commit](#prepare-commit)
- **Plumbing**: Lower-level scripts intended to be used by other scripts or for advanced workflows.
  - [Select Folder](#select-folder)

## Porcelain Commands

### Archive Meeting

This script helps you archive a meeting by combining transcripts and chat logs, generating an executive summary, generating detailed meeting notes (as if you took notes in the meeting), and updating notes. It guides you through selecting the folder with the transcript(s), processes the files, and updates your markdown notes with wikilinks to the transcript, summary, and detailed notes.

**Usage:**

```sh
/path/to/scripts/bin/archive-meeting \
  --transcripts-dir /path/to/Zoom/ \
  --target-dir /path/to/Notes/ \
  --executive-summary-prompt-path /path/to/meeting-summary.txt \
  --detailed-notes-prompt-path /path/to/meeting-detailed-notes.txt
```

### Create Weekly Note

This script helps you quickly create a new weekly note from a template and place it in your notes directory.

**Usage:**

```sh
/path/to/scripts/bin/create-weekly-note --template-path /path/to/weekly/notes/template.md --target-dir /path/to/weekly/notes
```

### Fetch GitHub Conversation

Fetch and export GitHub issue, pull request, or discussion data as structured JSON. This script retrieves all relevant data from a GitHub issue, pull request, or discussion URL using the GitHub CLI (`gh`). It outputs a single JSON object containing the main conversation and all comments, suitable for archiving or further processing.

**Usage:**

```sh
/path/to/scripts/bin/fetch-github-conversation <github_conversation_url>
```

The script will abort with an error message if the URL is not recognized or if any command fails.

### Prepare Commit

This script helps you generate a semantic commit message for your staged changes using an LLM. It copies the staged diff to your clipboard, prompts you for commit type and optional scope, and generates a commit message using the provided prompt template. You can review and regenerate the message as needed before committing. The final commit message is copied to your clipboard and pre-filled in the git commit editor.

> [!NOTE]
> If a file named `commit-message-guidelines.txt` exists in the directory where you run `prepare-commit`, its contents will be included in the LLM context (after the prompt template and before the commit type/scope header). This allows you to provide project specific commit message guidelines that will help the LLM generate better commit messages.

**Usage:**

```sh
/path/to/scripts/bin/prepare-commit \
  --commit-message-prompt-path /path/to/commit-prompt.txt \
  [--llm-model MODEL]
```

## Plumbing Commands

### Select Folder

This script takes a target directory as an argument and returns the 10 names of the most recently updated folders in that directory. It then lets you select a folder using arrow keys or fuzzy search (via `fzf`) and returns the full path of the selected folder.

**Usage:**

```sh
/path/to/scripts/bin/select-folder --target-dir /path/to/target
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to this project.

## Contributors

- [jonmagic](https://github.com/jonmagic)

## License

This project is licensed under the [ISC License](LICENSE).
