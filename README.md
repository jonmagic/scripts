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
  - [Extract Topics](#extract-topics)
  - [Fetch GitHub Conversation](#fetch-github-conversation)
  - [Summarize GitHub Conversation](#summarize-github-conversation)
  - [Prepare Commit](#prepare-commit)
  - [Prepare Pull Request](#prepare-pull-request)
- **Plumbing**: Lower-level scripts intended to be used by other scripts or for advanced workflows.
  - [Select Folder](#select-folder)

### Aliases

The raw scripts are useful but require a lot of typing so I recommend adding aliases to your shell configuration to make things easier. For example, here are my aliases (which can be added to your `.bashrc` or `.zshrc`):

```sh
alias cwn='/path/to/create-weekly-note --template-path /path/to/Templates/Week\ of\ \{\{date\}\}.md --target-dir /path/to/Weekly\ Notes/'
alias am='/path/to/archive-meeting --transcripts-dir ~/Documents/Zoom/ --target-dir /path/to --executive-summary-prompt-path /path/to/zoom-transcript-executive-summary.md --detailed-notes-prompt-path /path/to/transcript-meeting-notes.md'
alias commit='/path/to/prepare-commit --commit-message-prompt-path /path/to/commit-message.md'
alias fgc='/path/to/fetch-github-conversation'
alias et='/path/to/extract-topics --topics-prompt-path /path/to/topic-extraction.txt'
alias es='llm -f /path/to/github-conversation-executive-summary.md'
alias ppr='/path/to/prepare-pull-request --base-branch main --pr-body-prompt-path /path/to/pull-request-body.md'
```

All of the referenced prompts can be found here: https://github.com/jonmagic/prompts

## Porcelain Commands

### Archive Meeting

This script helps you archive a meeting by combining transcripts and chat logs, generating an executive summary, generating detailed meeting notes (as if you took notes in the meeting), and updating notes. It guides you through selecting the folder with the transcript(s), processes the files, and updates your markdown notes with wikilinks to the transcript, summary, and detailed notes.

**Usage:**

```sh
/path/to/archive-meeting \
  --transcripts-dir /path/to/Zoom/ \
  --target-dir /path/to/Notes/ \
  --executive-summary-prompt-path /path/to/meeting-summary.txt \
  --detailed-notes-prompt-path /path/to/meeting-detailed-notes.txt
```

### Create Weekly Note

This script helps you quickly create a new weekly note from a template and place it in your notes directory.

**Usage:**

```sh
/path/to/create-weekly-note --template-path /path/to/weekly/notes/template.md --target-dir /path/to/weekly/notes
```

### Fetch GitHub Conversation

Fetch and export GitHub issue, pull request, or discussion data as structured JSON. This script retrieves all relevant data from a GitHub issue, pull request, or discussion using the GitHub CLI (`gh`). It outputs a single JSON object containing the main conversation and all comments, suitable for archiving or further processing. Supports caching to avoid redundant API calls.

**Usage:**

```sh
/path/to/fetch-github-conversation <github_conversation_url> \
  [--cache-path <cache_root>] [--updated-at <iso8601>]
```

- `<github_conversation_url>`: A GitHub issue, pull request, or discussion URL (e.g. `https://github.com/octocat/Hello-World/issues/42`)
- `owner/repo/type/number`: Alternative input form (e.g. `octocat/Hello-World/issues/42`)
- `--cache-path <cache_root>`: (Optional) Root directory for caching. Data is stored as `conversations/<owner>/<repo>/<type>/<number>.json` under this path.
- `--updated-at <timestamp>`: (Optional) Only fetch if the remote conversation is newer than this ISO8601 timestamp (or the cached data).

**Examples:**

Fetch and print a GitHub issue:

```sh
/path/to/fetch-github-conversation https://github.com/octocat/Hello-World/issues/42
```

Fetch and cache a pull request, only if updated:

```sh
/path/to/fetch-github-conversation octocat/Hello-World/pull/123 --cache-path ./cache --updated-at 2024-05-01T00:00:00Z
```

The script will abort with an error message if the input is not recognized or if any command fails.

### Summarize GitHub Conversation

Generate an executive summary of a GitHub issue, pull request, or discussion using the `llm` CLI and a required prompt file. This script fetches or loads a cached conversation (using `fetch-github-conversation`), extracts the text content, and uses the `llm` CLI to generate a summary using the provided prompt file. Optionally, it saves the summary as a JSON file in the cache.

**Usage:**

```sh
/path/to/summarize-github-conversation <github_conversation_url> --executive-summary-prompt-path <prompt_path> [--cache-path <cache_root>] [--updated-at <iso8601>]
```

- `<github_conversation_url>`: A GitHub issue, pull request, or discussion URL (e.g. `https://github.com/octocat/Hello-World/issues/42`)
- `owner/repo/type/number`: Alternative input form (e.g. `octocat/Hello-World/issues/42`)
- `--executive-summary-prompt-path <prompt_path>`: **(Required)** Path to the prompt file to use for the executive summary. The prompt file should contain instructions for the LLM; the conversation text will be appended as input.
- `--cache-path <cache_root>`: (Optional) Root directory for caching. Summary is stored as `summaries/<owner>/<repo>/<type>/<number>.json` under this path.
- `--updated-at <timestamp>`: (Optional) Only fetch if the remote conversation is newer than this ISO8601 timestamp (or the cached data).

**Examples:**

Summarize a GitHub issue:

```sh
/path/to/summarize-github-conversation https://github.com/octocat/Hello-World/issues/42 --executive-summary-prompt-path /path/to/github-summary.txt
```

Summarize and cache a pull request, only if updated:

```sh
/path/to/summarize-github-conversation octocat/Hello-World/pull/123 --executive-summary-prompt-path /path/to/github-summary.txt --cache-path ./cache --updated-at 2024-05-01T00:00:00Z
```

The script will abort with an error message if the input is not recognized, if the prompt path is not provided, or if any command fails.

### Extract Topics

Extract key thematic topics or labels from a GitHub conversation using the `llm` CLI and a prompt file. This script fetches or loads a cached GitHub conversation (using `fetch-github-conversation`), extracts the text content, and uses the `llm` CLI to identify and extract thematic topics using the provided prompt file. Topics are returned as a JSON array of strings. Optionally, it saves the topics as a JSON file in the cache and can limit the number of topics extracted.

**Usage:**

```sh
/path/to/extract-topics <github_conversation_url> --topics-prompt-path <prompt_path> [--cache-path <cache_root>] [--updated-at <iso8601>] [--max-topics <number>]
```

- `<github_conversation_url>`: A GitHub issue, pull request, or discussion URL (e.g. `https://github.com/octocat/Hello-World/issues/42`)
- `owner/repo/type/number`: Alternative input form (e.g. `octocat/Hello-World/issues/42`)
- `--topics-prompt-path <prompt_path>`: **(Required)** Path to the prompt file to use for topic extraction. The prompt file should contain instructions for the LLM; the conversation text will be appended as input.
- `--cache-path <cache_root>`: (Optional) Root directory for caching. Topics are stored as `topics/<owner>/<repo>/<type>/<number>.json` under this path.
- `--updated-at <timestamp>`: (Optional) Only fetch if the remote conversation is newer than this ISO8601 timestamp (or the cached data).
- `--max-topics <number>`: (Optional) Maximum number of topics to extract from the conversation.

**Output Format:**

The script outputs a JSON array of strings to STDOUT, for example:
```json
["performance", "authentication", "database", "caching", "bug-fix"]
```

**Examples:**

Extract topics from a GitHub issue:

```sh
/path/to/extract-topics https://github.com/octocat/Hello-World/issues/42 --topics-prompt-path /path/to/topic-extraction.txt
```

Extract and cache topics from a pull request, limiting to 5 topics:

```sh
/path/to/extract-topics octocat/Hello-World/pull/123 --topics-prompt-path /path/to/topic-extraction.txt --cache-path ./cache --max-topics 5
```

The script will abort with an error message if the input is not recognized, if the prompt path is not provided, or if any command fails.

### Prepare Commit

This script helps you generate a semantic commit message for your staged changes using an LLM. It copies the staged diff to your clipboard, prompts you for commit type and optional scope, and generates a commit message using the provided prompt template. You can review and regenerate the message as needed before committing. The final commit message is copied to your clipboard and pre-filled in the git commit editor.

> [!NOTE]
> If a file named `commit-message-guidelines.txt` exists in the directory where you run `prepare-commit`, its contents will be included in the LLM context (after the prompt template and before the commit type/scope header). This allows you to provide project specific commit message guidelines that will help the LLM generate better commit messages.

**Usage:**

```sh
/path/to/prepare-commit \
  --commit-message-prompt-path /path/to/commit-prompt.txt \
  [--llm-model MODEL]
```

### Prepare Pull Request

This script helps you generate a pull request title and body based on commits between your current branch and the base branch. It uses an LLM to analyze your commit messages and diffs to generate a meaningful PR description. You can review and edit both the title and body before creating the PR using the GitHub CLI. If you choose not to create the PR immediately, the title and body are copied to your clipboard for later use.

**Usage:**

```sh
/path/to/prepare-pull-request \
  --base-branch main \
  --pr-body-prompt-path /path/to/pr-prompt.txt \
  [--llm-model MODEL]
```

- `--base-branch`: The name of the base branch to compare against (e.g., main, master, develop)
- `--pr-body-prompt-path`: Path to the prompt file for generating the PR body
- `--llm-model`: (Optional) Specify a specific LLM model to use

## Plumbing Commands

### Select Folder

This script takes a target directory as an argument and returns the 10 names of the most recently updated folders in that directory. It then lets you select a folder using arrow keys or fuzzy search (via `fzf`) and returns the full path of the selected folder.

**Usage:**

```sh
/path/to/select-folder --target-dir /path/to/target
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to this project.

## Contributors

- [jonmagic](https://github.com/jonmagic)

## License

This project is licensed under the [ISC License](LICENSE).
