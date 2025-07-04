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
  - [Fetch GitHub Conversations](#fetch-github-conversations)
  - [Index Summary](#index-summary)
  - [Index Summaries](#index-summaries)
  - [Summarize GitHub Conversation](#summarize-github-conversation)
  - [Prepare Commit](#prepare-commit)
  - [Prepare Pull Request](#prepare-pull-request)
- **Plumbing**: Lower-level scripts intended to be used by other scripts or for advanced workflows.
  - [Search GitHub Conversations](#search-github-conversations)
  - [Select Folder](#select-folder)
  - [Vector Upsert](#vector-upsert)

### Aliases

The raw scripts are useful but require a lot of typing so I recommend adding aliases to your shell configuration to make things easier. For example, here are my aliases (which can be added to your `.bashrc` or `.zshrc`):

```sh
alias cwn='/path/to/create-weekly-note --template-path /path/to/Templates/Week\ of\ \{\{date\}\}.md --target-dir /path/to/Weekly\ Notes/'
alias am='/path/to/archive-meeting --transcripts-dir ~/Documents/Zoom/ --target-dir /path/to --executive-summary-prompt-path /path/to/zoom-transcript-executive-summary.md --detailed-notes-prompt-path /path/to/transcript-meeting-notes.md'
alias commit='/path/to/prepare-commit --commit-message-prompt-path /path/to/commit-message.md'
alias fgc='/path/to/fetch-github-conversation'
alias et='/path/to/extract-topics --topics-prompt-path /path/to/topic-extraction.txt'
alias es='llm -f /path/to/github-conversation-executive-summary.md'
alias idx='/path/to/index-summary --executive-summary-prompt-path /path/to/github-conversation-executive-summary.md --topics-prompt-path /path/to/topic-extraction.txt --collection github-conversations --skip-if-up-to-date'
alias bidx='/path/to/index-summaries --executive-summary-prompt-path /path/to/github-conversation-executive-summary.md --topics-prompt-path /path/to/topic-extraction.txt --collection github-conversations --cache-path ./cache --skip-if-up-to-date'
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

### Fetch GitHub Conversations

Fetch and export GitHub issue, pull request, or discussion data for multiple URLs at once. This script uses `fetch-github-conversation` under the hood to process multiple GitHub conversations, accepting URLs either from stdin (piped) or from a file. It supports both plain text URLs and JSON input from `search-github-conversations`, automatically using updated_at timestamps for efficient caching. It passes through all CLI options to the underlying script and streams JSON output to stdout.

**Usage:**

```sh
/path/to/fetch-github-conversations [options] <file_path>
# or
command | /path/to/fetch-github-conversations [options]
```

- `<file_path>`: Path to file containing GitHub URLs (plain text, one per line) or JSON data
- Options are passed through to `fetch-github-conversation`:
  - `--cache-path <cache_root>`: (Optional) Root directory for caching
  - `--updated-at <timestamp>`: (Optional) Only fetch if newer than this ISO8601 timestamp

**Input Formats:**

1. **Plain text URLs**: One URL per line (existing format)
2. **JSON from search-github-conversations**: Array of objects with `url` and `updated_at` fields

**Examples:**

Fetch multiple conversations from a plain text file:

```sh
/path/to/fetch-github-conversations urls.txt
```

Fetch from stdin with plain text URLs:

```sh
echo "https://github.com/octocat/Hello-World/issues/42" | /path/to/fetch-github-conversations --cache-path ./cache
```

**Pipeline with search-github-conversations** (recommended workflow):

```sh
# Search for conversations and fetch them with automatic timestamp optimization
/path/to/search-github-conversations 'repo:octocat/Hello-World created:>2025' | \
  /path/to/fetch-github-conversations --cache-path ./cache
```

**Complete workflow example** (search → fetch → summarize → index):

```sh
# Step 1: Search for recent conversations
/path/to/search-github-conversations 'repo:octocat/Hello-World created:>2025' > recent_conversations.json

# Step 2: Fetch full conversation data with caching
cat recent_conversations.json | /path/to/fetch-github-conversations --cache-path ./cache

# Step 3: Extract URLs and generate summaries
cat recent_conversations.json | jq -r '.[].url' | while read url; do
  /path/to/summarize-github-conversation "$url" \
    --executive-summary-prompt-path /path/to/summary-prompt.txt \
    --cache-path ./cache
done

# Step 4: Index summaries for semantic search
cat recent_conversations.json | jq -r '.[].url' | while read url; do
  /path/to/index-summary "$url" \
    --executive-summary-prompt-path /path/to/summary-prompt.txt \
    --topics-prompt-path /path/to/topics-prompt.txt \
    --collection github-conversations \
    --cache-path ./cache \
    --skip-if-up-to-date
done
```

Fetch multiple conversations with global timestamp check:

```sh
/path/to/fetch-github-conversations --cache-path ./cache --updated-at 2024-05-01T00:00:00Z urls.txt
```

**Key Benefits of JSON Input:**

When using JSON input from `search-github-conversations`, each conversation is fetched with its individual `updated_at` timestamp, providing optimal caching efficiency. This means conversations that haven't been updated since the last fetch will be served from cache, while only recently updated conversations will make new API calls.

The script continues processing even if individual URLs fail and outputs error messages to stderr for any failures.

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

### Index Summary

Index a GitHub conversation summary in a vector database (Qdrant) for semantic search. This script orchestrates the complete pipeline: fetching conversation data, generating a summary, extracting topics, building metadata, and storing the summary as a vector embedding in Qdrant. It combines the functionality of `fetch-github-conversation`, `summarize-github-conversation`, `extract-topics`, and `vector-upsert` into a single workflow.

**Usage:**

```sh
/path/to/index-summary <github_conversation_url> \
  --executive-summary-prompt-path <summary_prompt_path> \
  --topics-prompt-path <topics_prompt_path> \
  --collection <collection_name> \
  [options]
```

- `<github_conversation_url>`: A GitHub issue, pull request, or discussion URL (e.g. `https://github.com/octocat/Hello-World/issues/42`)
- `--executive-summary-prompt-path <path>`: **(Required)** Path to the prompt file for generating executive summaries
- `--topics-prompt-path <path>`: **(Required)** Path to the prompt file for extracting topics
- `--collection <name>`: **(Required)** Qdrant collection name where the vector will be stored
- `--cache-path <path>`: (Optional) Root directory for caching conversation data and processing results
- `--updated-at <timestamp>`: (Optional) Only process if the remote conversation is newer than this ISO8601 timestamp
- `--model <model>`: (Optional) Embedding model to use for vector generation
- `--qdrant-url <url>`: (Optional) Qdrant server URL (default: http://localhost:6333)
- `--max-topics <number>`: (Optional) Maximum number of topics to extract
- `--skip-if-up-to-date`: (Optional) Skip indexing if vector exists and is up-to-date based on updated_at timestamp

**Metadata Fields:**

The script creates a flat JSON metadata payload that includes:
- `url`, `owner`, `repo`, `type`, `number`, `title`, `author`, `state`
- `created_at`, `updated_at`, `closed_at` (if applicable), `indexed_at`
- `topics` (comma-separated list)
- Type-specific fields:
  - Issues: `labels`, `milestone`
  - Pull Requests: `merged`, `merged_at`, `base_branch`, `head_branch`
  - Discussions: `category`, `answered`

**Examples:**

Index a GitHub issue summary:

```sh
/path/to/index-summary https://github.com/octocat/Hello-World/issues/42 \
  --executive-summary-prompt-path /path/to/summary-prompt.txt \
  --topics-prompt-path /path/to/topics-prompt.txt \
  --collection github-conversations
```

Index with caching, custom model, and timestamp optimization:

```sh
/path/to/index-summary octocat/Hello-World/pull/123 \
  --executive-summary-prompt-path /path/to/summary-prompt.txt \
  --topics-prompt-path /path/to/topics-prompt.txt \
  --collection github-conversations \
  --cache-path ./cache \
  --model text-embedding-3-small \
  --skip-if-up-to-date
```

**Requirements:**
- A running Qdrant server (default: localhost:6333)
- Valid LLM API credentials configured with the `llm` CLI
- All prompt files must exist and be readable

### Index Summaries

Bulk index multiple GitHub conversations into Qdrant for semantic search. This script orchestrates bulk indexing by running `index-summary` on each URL from either a file or stdin. It supports both plain text URLs and JSON input with updated_at timestamps for efficient caching.

**Usage:**

```sh
./path/to/index-summaries [options] <file_path>
# or
command | ./path/to/index-summaries [options]
```

- `<file_path>`: Path to file containing GitHub URLs (plain text, one per line) or JSON data
- All options are passed through to `index-summary`

**Required Options:**

- `--executive-summary-prompt-path <path>`: Path to the prompt file for generating executive summaries
- `--topics-prompt-path <path>`: Path to the prompt file for extracting topics  
- `--collection <name>`: Qdrant collection name where vectors will be stored

**Optional Options:**

- `--cache-path <path>`: Root directory for caching conversation data and processing results
- `--updated-at <timestamp>`: Only process if remote conversation is newer (overrides JSON timestamps)
- `--model <model>`: Embedding model to use for vector generation
- `--qdrant-url <url>`: Qdrant server URL (default: http://localhost:6333)
- `--max-topics <number>`: Maximum number of topics to extract
- `--skip-if-up-to-date`: Skip indexing if vector exists and is up-to-date

**Input Formats:**

1. **Plain text URLs**: One URL per line
2. **JSON from search-github-conversations**: Array of objects with `url` and `updated_at` fields

**Examples:**

Bulk index from a plain text file:

```sh
./path/to/index-summaries \
  --executive-summary-prompt-path ./prompts/executive-summary.txt \
  --topics-prompt-path ./prompts/topics.txt \
  --collection github-conversations \
  urls.txt
```

Bulk index from search results with automatic timestamp optimization:

```sh
./path/to/search-github-conversations 'repo:octocat/Hello-World created:>2025' | \
  ./path/to/index-summaries \
    --executive-summary-prompt-path ./prompts/summary.txt \
    --topics-prompt-path ./prompts/topics.txt \
    --collection github-conversations \
    --cache-path ./cache \
    --skip-if-up-to-date
```

**Complete workflow example** (search → bulk index):

```sh
# Step 1: Search for recent conversations and bulk index them
./path/to/search-github-conversations 'repo:octocat/Hello-World created:>2025' | \
  ./path/to/index-summaries \
    --executive-summary-prompt-path /path/to/summary-prompt.txt \
    --topics-prompt-path /path/to/topics-prompt.txt \
    --collection github-conversations \
    --cache-path ./cache \
    --skip-if-up-to-date
```

**Key Benefits:**

- **Bulk processing**: Process multiple conversations in a single command
- **Automatic timestamp optimization**: When using JSON input, each conversation uses its individual `updated_at` timestamp for optimal caching
- **Error resilience**: Continues processing even if individual URLs fail, with errors logged to stderr
- **JSON output**: Streams JSON objects to stdout for successful indexing operations
- **Pipeline-friendly**: Designed to work seamlessly with `search-github-conversations`

**Output Format:**

For each successfully indexed conversation, outputs a JSON object:

```json
{"url":"https://github.com/owner/repo/issues/42","status":"indexed"}
```

The script continues processing even if individual URLs fail and outputs error messages to stderr for any failures.

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

### Search GitHub Conversations

Search GitHub conversations (issues, pull requests, discussions) using a GitHub search query string and the GraphQL API. This script aggregates search results and returns minimal metadata for each conversation, making it ideal for use in pipelines with other tools like `fetch-github-conversation`.

**Usage:**

```sh
/path/to/search-github-conversations '<search_query>'
```

- `<search_query>`: A GitHub search query string using standard GitHub search syntax

**Key Features:**

- **Automatic type detection**: Inspects query for `is:issue`, `is:pr`, `is:discussion` modifiers to determine what to search
- **Fallback search**: If no type specified, searches both issues/PRs and discussions automatically
- **Pagination**: Handles pagination up to 1000 items per conversation type
- **Consistent output**: Returns JSON array with `updated_at` and `url` for each result
- **Sorted results**: Results are sorted by `updated_at` in descending order (most recent first)

**Examples:**

Search for pull requests only:

```sh
/path/to/search-github-conversations 'repo:octocat/Hello-World is:pr created:>2025'
```

Search for all conversation types in a specific date range:

```sh
/path/to/search-github-conversations 'repo:octocat/Hello-World created:2025-01-01..2025-06-30'
```

Search for discussions only:

```sh
/path/to/search-github-conversations 'repo:octocat/Hello-World is:discussion'
```

Search across multiple repositories:

```sh
/path/to/search-github-conversations 'org:octocat is:issue state:open created:>2025'
```

Search with specific labels or keywords:

```sh
/path/to/search-github-conversations 'repo:octocat/Hello-World is:issue label:bug,enhancement in:title,body performance'
```

**Example Output:**

```json
[
  {
    "updated_at": "2025-06-20T09:42:11Z",
    "url": "https://github.com/octocat/Hello-World/issues/123"
  },
  {
    "updated_at": "2025-06-18T14:23:05Z",
    "url": "https://github.com/octocat/Hello-World/pull/456"
  },
  {
    "updated_at": "2025-06-15T10:00:00Z",
    "url": "https://github.com/octocat/Hello-World/discussions/789"
  }
]
```

**Requirements:**
- The `gh` CLI must be installed and authenticated
- Valid GitHub search query syntax

**Error Handling:**
- Aborts with clear error message for invalid queries
- Aborts if `gh` CLI is not authenticated
- Handles GraphQL API errors and rate limits

### Select Folder

This script takes a target directory as an argument and returns the 10 names of the most recently updated folders in that directory. It then lets you select a folder using arrow keys or fuzzy search (via `fzf`) and returns the full path of the selected folder.

**Usage:**

```sh
/path/to/select-folder --target-dir /path/to/target
```

### Vector Upsert

Generic tool for embedding arbitrary text and upserting vectors with metadata into Qdrant collections. This is a low-level plumbing script that handles the embedding generation and Qdrant integration, designed to be used by higher-level orchestration scripts like `index-summary` or in custom workflows.

**Usage:**

```sh
echo "text to embed" | /path/to/vector-upsert \
  --collection <collection_name> \
  --metadata '<flat_json_object>' \
  [options]
```

- `--collection <name>`: **(Required)** Qdrant collection name where the vector will be stored
- `--metadata <json>`: **(Required)** Flat JSON metadata object with optional arrays of primitive values (no nested objects)
- `--vector-id-key <key>`: (Optional) Key in metadata that contains the main text for ID generation (default: use stdin content)
- `--model <model>`: (Optional) Embedding model to use (default: text-embedding-3-small)
- `--qdrant-url <url>`: (Optional) Qdrant server URL (default: http://localhost:6333)
- `--skip-if-up-to-date <timestamp_key>`: (Optional) Skip upserting if vector exists and timestamp in specified metadata key is up-to-date

**Key Features:**

- **Flat JSON validation**: Metadata must be a flat JSON object with optional arrays of primitive values (strings, numbers, booleans, null); the script will abort if nested objects or arrays containing nested structures are detected
- **Stable vector IDs**: Generates deterministic SHA-256 hashes for consistent vector identification
- **Auto-collection creation**: Creates Qdrant collections automatically if they don't exist
- **Error handling**: Clear error messages for embedding failures, Qdrant connectivity issues, and validation errors

**Examples:**

Embed a simple text with metadata:

```sh
echo "This is a summary of a GitHub issue" | /path/to/vector-upsert \
  --collection github-issues \
  --metadata '{"url": "https://github.com/owner/repo/issues/123", "title": "Bug report", "author": "username"}'
```

Embed with array metadata (topics, labels, etc.):

```sh
echo "Summary of feature discussion" | /path/to/vector-upsert \
  --collection github-conversations \
  --metadata '{"url": "https://github.com/owner/repo/issues/456", "topics": ["performance", "caching", "database"], "labels": ["enhancement", "priority-high"]}'
```

Use a specific embedding model and Qdrant server:

```sh
echo "Document content" | /path/to/vector-upsert \
  --collection documents \
  --metadata '{"title": "Document Title", "category": "technical"}' \
  --model text-embedding-3-large \
  --qdrant-url http://remote-qdrant:6333
```

Use timestamp-based optimization to skip upserting if content is up-to-date:

```sh
echo "Updated summary text" | /path/to/vector-upsert \
  --collection summaries \
  --metadata '{"url": "unique-identifier", "updated_at": "2024-05-15T10:30:00Z", "source": "github"}' \
  --skip-if-up-to-date updated_at
```

Specify which metadata field to use for ID generation:

```sh
echo "Summary text" | /path/to/vector-upsert \
  --collection summaries \
  --metadata '{"html_url": "unique-identifier", "summary": "Summary text", "source": "github"}' \
  --vector-id-key html_url
```

**Error Conditions:**

The script will abort with clear error messages for:
- Missing required arguments (`--collection`, `--metadata`)
- Invalid JSON or nested objects/arrays in `--metadata` (arrays of primitives are allowed)
- Empty text input via stdin
- Embedding generation failures (invalid model, API issues)
- Qdrant connectivity or API errors
- Missing dependencies (`llm`, `curl`)

### Semantic Search GitHub Conversations

Executes semantic search against conversation summaries stored in Qdrant. This plumbing command embeds a user query using the `llm` CLI and searches for the most similar conversations using vector similarity with support for metadata filtering.

**Usage:**

```sh
/path/to/semantic-search-github-conversations [options] "free-text query"
```

**Options:**

- `-c, --collection NAME`: Qdrant collection name (default: summaries)
- `-f, --filter KEY:VALUE`: Filter by metadata (repeatable for multiple filters)
- `-n, --limit N`: Maximum number of results to return (default: 10)
- `--score-threshold N`: Minimum similarity score threshold (0.0-1.0)
- `--url URL`: Qdrant base URL (default: http://localhost:6333)
- `-v, --verbose`: Dump request/response JSON for debugging
- `--json`: Output results as JSON array instead of formatted text
- `-h, --help`: Show help message

**Filter Syntax:**

Multiple `--filter` flags with the same key are OR-combined, while different keys are AND-combined:

```bash
# Exact matches
--filter repo:rails/rails
--filter owner:github  
--filter type:issue
--filter state:open
--filter number:123

# Date ranges (YYYY-MM-DD format)
--filter created_after:2025-01-01
--filter created_before:2025-06-30
--filter updated_after:2025-01-01
--filter updated_before:2025-06-30
--filter indexed_after:2025-01-01
--filter indexed_before:2025-06-30

# Substring matches
--filter title:security
--filter author:octocat

# Topic matching  
--filter topics:security
--filter topics:bug
```

**Examples:**

Basic semantic search:

```sh
/path/to/semantic-search-github-conversations "authentication vulnerability"
```

Search with repository and topic filters:

```sh
/path/to/semantic-search-github-conversations -n 5 \
  --filter repo:rails/rails \
  --filter topics:security \
  --filter topics:bug \
  --filter created_after:2025-01-01 \
  --filter created_before:2025-06-30 \
  "credential leak mitigation"
```

Output as JSON for pipeline processing:

```sh
/path/to/semantic-search-github-conversations --json \
  --filter repo:octocat/Hello-World \
  "performance optimization" | jq '.[].url'
```

Debug Qdrant requests and responses:

```sh
/path/to/semantic-search-github-conversations --verbose \
  --collection github-summaries \
  --url http://localhost:6333 \
  "database performance issues"
```

**Output Format:**

Default formatted output shows:
- Repository name and URL with similarity score
- Conversation title  
- Summary snippet (truncated to 160 characters)
- Labels and topics as comma-separated lists

JSON output (`--json`) returns an array with `url`, `updated_at`, `score`, and metadata fields compatible with other pipeline scripts.

**Requirements:**
- `llm` CLI with embedding model support
- Running Qdrant server with indexed conversation summaries
- Conversations must be indexed using `index-summary` or `index-summaries`

**Error Handling:**
- Exits 1 with usage message if no query provided
- Exits 1 with error message for embedding failures or Qdrant connectivity issues  
- Uses verbose mode to troubleshoot request/response JSON

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to this project.

## Contributors

- [jonmagic](https://github.com/jonmagic)

## License

This project is licensed under the [ISC License](LICENSE).
