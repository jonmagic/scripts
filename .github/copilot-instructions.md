# Copilot Instructions

## Repository Overview

Personal productivity scripts for managing markdown-based notes, GitHub workflows, and AI-powered content generation. The codebase implements a complete semantic search pipeline for GitHub conversations, combining vector databases, LLM integration, and interactive research workflows.

## Core Architecture Patterns

### Data Pipeline Architecture
The system follows a three-stage pipeline: **fetch → process → index**
1. **Fetch**: `fetch-github-conversation` retrieves GitHub issues/PRs/discussions via GraphQL API
2. **Process**: `summarize-github-conversation` + `extract-topics` generate AI summaries and topic extraction
3. **Index**: `vector-upsert` embeds summaries into Qdrant vector database for semantic search

### Multi-Modal Workflow Engine
Uses `lib/pocketflow.rb` for orchestrating complex workflows with retry logic and state management:
- **Node lifecycle**: `prep() → exec() → post()` with automatic error handling
- **Flow orchestration**: Chains nodes with conditional routing (`node.on("action", next_node)`)
- **Research Agent**: `github-conversations-research-agent` implements multi-turn AI research with clarifying questions

### Caching & Data Persistence
Structured caching hierarchy optimizes expensive operations:
```
data/
  conversations/github/{owner}/{repo}/{type}/{number}.json  # Raw API responses
  summaries/github/{owner}/{repo}/{type}/{number}.json     # AI summaries
  topics/github/{owner}/{repo}/{type}/{number}.json        # Extracted topics
  qdrant/                                                  # Vector database storage
```

## Essential Integration Patterns

### LLM Integration via External CLI
- **Never import LLM libraries directly** - always use `llm` CLI via `Open3.capture3`
- **Prompt templating**: Use `{{variable}}` syntax with `fill_template()` helper
- **Model specification**: Support `--llm-model` flag with ENV["LLM_MODEL"] fallback
- **Embedding generation**: Standard pattern: `llm embed -m text-embedding-3-small -f json -c "text"`

### Vector Database (Qdrant) Patterns
- **Flat JSON metadata only**: Nested objects are explicitly forbidden; arrays of primitives allowed
- **Stable vector IDs**: Use UUIDv5 generation based on content for deterministic IDs
- **Auto-collection creation**: Scripts auto-create collections with cosine distance
- **Timestamp optimization**: `--skip-if-up-to-date` checks remote timestamps before processing

### GitHub API Integration
- **GraphQL via `gh` CLI**: Never use REST when GraphQL available (`search-github-conversations`)
- **Conversation normalization**: Convert all issues/PRs/discussions to common JSON schema
- **URL parsing**: Support both full URLs and `owner/repo/type/number` shorthand
- **Rate limit handling**: Built into `gh` CLI, scripts assume authentication is pre-configured

## Critical Workflow Commands

### Research & Discovery
```bash
# Standard research pipeline (most important workflow)
bin/search-github-conversations 'repo:owner/repo created:>2025' | \
  bin/index-summaries --executive-summary-prompt-path prompts/summary.txt \
                      --topics-prompt-path prompts/topics.txt \
                      --collection github-conversations --cache-path data

# Multi-turn AI research with clarifying questions
bin/github-conversations-research-agent "question" --collection github-conversations
```

### Bulk Processing Patterns
- **Pipeline-friendly**: Most scripts accept stdin/stdout for chaining
- **Batch operations**: `index-summaries`, `fetch-github-conversations` handle bulk processing
- **Error resilience**: Continue processing even if individual items fail
- **Progress tracking**: Use `log.txt` to track completed work and enable resumption

## Development Conventions

### Script Structure (Ruby)
```ruby
#!/usr/bin/env ruby

# Required imports for most scripts
require "json"
require "open3"
require "optparse"
require "shellwords"

# Standard helpers (copy these patterns)
def run_cmd(cmd)
  stdout, stderr, status = Open3.capture3(cmd)
  abort "Command failed: #{cmd}\n#{stderr}" unless status.success?
  stdout.strip
end

def check_dependency(cmd)
  system("which #{cmd} > /dev/null 2>&1") || abort("Required dependency '#{cmd}' not found in PATH.")
end
```

### Error Handling Patterns
- **Fail fast**: Use `abort "message"` for user-facing errors
- **Dependency validation**: Always check external commands before use
- **JSON validation**: Parse and validate all JSON inputs/outputs
- **Graceful degradation**: Cache misses should not break workflows

### CLI Argument Patterns
- **OptionParser standard**: Use consistent `--flag VALUE` patterns
- **Required vs optional**: Mark required args in usage, provide sensible defaults
- **Prompt file paths**: Always require explicit prompt file paths (no embedded prompts)
- **Cache path consistency**: Use `--cache-path` for all caching operations

### Integration Dependencies
Core external tools (check via `bin/bootstrap`):
- `fzf` - Fuzzy finder for interactive selection
- `llm` - LLM CLI for embeddings and chat completion
- `gh` - GitHub CLI for API access
- `qdrant` - Vector database (usually localhost:6333)

### Data Modeling Patterns
- **Flat metadata**: Vector payloads must be flat JSON (no nested objects)
- **ISO 8601 timestamps**: Consistent date formatting for comparisons
- **Topic arrays**: Topics stored as string arrays for filtering
- **URL as primary key**: GitHub URLs serve as unique identifiers across all scripts

## File Formatting
- Always insert a final newline whenever you create a new file
- Trim final newlines to ensure only one newline at the end of files
- Trim trailing whitespace from all lines
- Use snake_case for variables and methods in Ruby
- Use descriptive method names with docstring comments
