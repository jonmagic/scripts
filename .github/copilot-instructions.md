# Copilot Instructions

## Repository Overview

Personal productivity scripts for managing markdown-based notes, GitHub workflows, and LLM-assisted content generation. All scripts are designed to integrate with external tools (fzf, llm CLI, GitHub CLI) to create seamless note-taking and archival workflows.

## Core Commands

### Setup & Dependencies
- `bin/bootstrap` - Install required dependencies (homebrew, fzf, llm, gh, bundler, gems)
- `Gemfile` - Ruby dependency management
- `bundle install` - Install Ruby gems

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
Comprehensive test suite using minitest with both unit and integration tests. All new functionality should include tests.

**Test Structure:**
```
test/
├── test_helper.rb      # Shared test utilities
├── unit/               # Unit tests for lib modules
├── integration/        # End-to-end script tests
└── example_test.rb     # Basic infrastructure test
```

**Running Tests:**
- `rake test` - Run all tests
- `rake unit` - Run only unit tests
- `rake integration` - Run only integration tests
- `rake stats` - Show test statistics

**Continuous Integration:**
- GitHub Actions CI workflow runs tests on Ruby 3.0, 3.1, 3.2, and 3.3
- Automatically installs system dependencies (fzf, gh, llm)
- Runs full test suite and reports statistics

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
lib/           # Shared Ruby modules and utilities
test/          # Test suite (unit and integration tests)
data/          # Cached data (gitignored)
  conversations/  # GitHub conversation cache
  summaries/      # AI-generated summaries
```

### Shared Libraries
Common functionality is extracted into reusable modules in `lib/`:
- **ErrorHandling**: Consistent error handling with `error_exit`
- **DependencyChecker**: Command dependency validation with `check_dependency`
- **LlmUtils**: LLM model flag handling and execution utilities
- **ClipboardUtils**: Cross-platform clipboard functionality
- **ShellUtils**: Safe shell command execution with error handling
- **MeetingFileUtils**: Meeting-specific file operations and utilities
- **LlmWorkflowUtils**: Complex LLM workflow operations

## Code Style & Patterns

### File Formatting
- Always insert a final newline at the end of files
- Trim final newlines to ensure only one newline at file end
- Trim trailing whitespace from all lines

### Ruby Scripts
- Use `#!/usr/bin/env ruby` shebang
- Import shared modules: `require 'error_handling'`, `include ErrorHandling`
- OptionParser for CLI argument handling
- Open3.capture3 for shell command execution (or use ShellUtils module)
- JSON.pretty_generate for output formatting
- Descriptive method names with docstring comments
- Snake_case for variables and methods

### Error Handling
- Use `error_exit("message")` from ErrorHandling module for fatal errors
- Use `check_dependency("command")` from DependencyChecker module
- Validate CLI arguments and provide usage messages
- Always handle missing files and invalid inputs gracefully

### Using Shared Modules
Scripts should import and use shared modules instead of duplicating code:

```ruby
# Add lib directory to load path
$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

# Import required modules
require 'error_handling'
require 'dependency_checker'
require 'llm_utils'

# Include functionality
include ErrorHandling
include DependencyChecker
include LlmUtils
```

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
- Import and use shared modules from `lib/` directory
- Include usage documentation in script comments
- Add dependency checks using DependencyChecker module
- Update README.md with new command documentation
- **Add tests**: Create integration test in `test/integration/` for new scripts

### Adding New Shared Functionality
- Extract common patterns into modules in `lib/` directory
- Use descriptive module names and follow existing patterns
- Add comprehensive unit tests in `test/unit/` for new modules
- Update existing scripts to use new shared functionality
- Document module usage in these copilot instructions

### Test-Driven Development
- Write integration tests first to capture expected behavior
- Extract and test shared functionality with unit tests
- Run tests frequently: `rake test` during development
- Ensure all tests pass before committing changes
- Aim for high test coverage of critical functionality

### External Integrations
- Always check for tool availability before use
- Provide clear error messages for missing dependencies
- Use standard CLI patterns for consistency
- Cache expensive operations when possible

### Dependency Management
- Use `Gemfile` for Ruby gem dependencies
- Run `bundle install` after adding new gems
- Update `bin/bootstrap` if new system dependencies are needed
- CI workflow automatically tests across multiple Ruby versions

### Markdown Processing
- Maintain wikilink compatibility for note cross-references
- Use ISO 8601 date formats consistently
- Structure files for semantic search and AI processing
