# Copilot Instructions

## Repository Overview

Personal productivity scripts for managing markdown-based notes, GitHub workflows, and LLM-assisted content generation. All scripts are designed to integrate with external tools (fzf, llm CLI, GitHub CLI) to create seamless note-taking and archival workflows.

## Core Commands

### Setup & Dependencies
- `bin/bootstrap` - Install required dependencies (homebrew, fzf, llm, gh)

### Main Scripts (Porcelain)
- `bin/create-weekly-note --template-path TEMPLATE --target-dir DIR` - Generate weekly notes from templates
- `bin/archive-meeting --transcripts-dir DIR --target-dir DIR --executive-summary-prompt-path FILE --detailed-notes-prompt-path FILE` - Archive meetings with AI summaries
- `bin/fetch-github-conversation URL [--cache-path DIR] [--updated-at ISO8601]` - Fetch GitHub issues/PRs/discussions as JSON
- `bin/summarize-github-conversation URL --executive-summary-prompt-path FILE [--cache-path DIR]` - Generate AI summaries of GitHub conversations
- `bin/prepare-commit --commit-message-prompt-path FILE [--llm-model MODEL]` - Generate semantic commit messages
- `bin/prepare-pull-request --base-branch BRANCH --pr-body-prompt-path FILE [--llm-model MODEL]` - Generate PR titles and descriptions

### Utility Scripts (Plumbing)
- `bin/select-folder --target-dir DIR` - Interactive folder selection with fzf

### Testing
No formal test suite. Scripts are tested manually and used daily in production workflows.

## Architecture

### Languages & Tools
- **Ruby**: Primary scripting language for complex data processing
- **Bash**: Simple setup and dependency management scripts
- **External Dependencies**: fzf (fuzzy finder), llm CLI (LLM interface), gh (GitHub CLI)

### Data Flow
- Scripts operate on markdown files in structured directory hierarchies
- GitHub data is fetched via API and cached as JSON
- LLM integration through external `llm` CLI tool with prompt files
- All outputs are markdown or JSON for easy integration

### File Organization
```
bin/           # Executable scripts (all chmod +x)
data/          # Cached data (gitignored)
  conversations/  # GitHub conversation cache
  summaries/      # AI-generated summaries
```

## Code Style & Patterns

### File Formatting
- Always insert a final newline at the end of files
- Trim final newlines to ensure only one newline at file end
- Trim trailing whitespace from all lines

### Ruby Scripts
- Use `#!/usr/bin/env ruby` shebang
- OptionParser for CLI argument handling
- Open3.capture3 for shell command execution
- JSON.pretty_generate for output formatting
- Descriptive method names with docstring comments
- Snake_case for variables and methods

### Error Handling
- Use `abort "message"` for fatal errors with user-friendly messages
- Check for required dependencies and files before proceeding
- Validate CLI arguments and provide usage messages

### Shell Integration
- Use Open3 for safe shell command execution
- Always check command exit status before proceeding
- Pipe data through stdin when possible (e.g., fzf integration)

### Data Processing
- Convert camelCase API responses to snake_case
- Filter and normalize GitHub API responses for consistency
- Cache expensive API calls with timestamp-based invalidation

## Development Guidelines

### Adding New Scripts
- Place executable scripts in `bin/` directory
- Use descriptive filenames without extensions
- Include usage documentation in script comments
- Add dependency checks where needed
- Update README.md with new command documentation

### External Integrations
- Always check for tool availability before use
- Provide clear error messages for missing dependencies
- Use standard CLI patterns for consistency
- Cache expensive operations when possible

### Markdown Processing
- Maintain wikilink compatibility for note cross-references
- Use ISO 8601 date formats consistently
- Structure files for semantic search and AI processing
