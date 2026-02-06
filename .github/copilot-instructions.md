# Copilot Instructions for jonmagic/scripts

## Overview

This is a TypeScript monorepo for personal automation tools. It uses **Bun** exclusively as the package manager and runtime.

## Critical Rules

### Bun Only - No npm/yarn/pnpm

- **ALWAYS** use `bun` commands, never `npm`, `yarn`, or `pnpm`
- **NEVER** create or commit `package-lock.json`, `yarn.lock`, or `pnpm-lock.yaml`
- The only lock file should be `bun.lock`

### Commands

```bash
bun install            # Install dependencies
bun run build          # Build all packages
bun test               # Run all tests
bun test path/to/file  # Run a single test file
bun run lint           # Lint
bun run typecheck      # Type check
```

### Before Committing

```bash
bun run typecheck && bun run lint && bun test && bun run build
```

### Commits

- Use semantic commit format: `type(scope): description` (e.g., `feat(vscode): add sidebar cache`)
- Common types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`
- Scope is typically the package name: `core`, `cli`, `vscode`, `raycast`
- **Commit after completing each logical unit of work** — don't accumulate multiple unrelated changes
- When finishing a planned task successfully, commit the changes before marking complete

### Package Structure

- `packages/core` - Shared utilities (`@jonmagic/scripts-core`) — other packages depend on this
- `packages/cli` - CLI tools (`@jonmagic/scripts-cli`)
- `packages/vscode` - VS Code extension (uses `code-insiders`)
- `packages/raycast` - Raycast extension

### Adding New CLI Commands

1. Create implementation in `packages/cli/src/your-command.ts`
2. Export from `packages/cli/src/index.ts`
3. Create CLI entrypoint in `packages/cli/bin/your-command`:
   - Start with `#!/usr/bin/env bun` shebang
   - Import from `../src/your-command.js` (bun resolves .ts)
   - Use `node:util` `parseArgs` for argument parsing
4. Make executable: `chmod +x packages/cli/bin/your-command`
5. Add to `bin` in `packages/cli/package.json`

### VS Code Extension

The extension (`packages/vscode`) provides utilities for a "Brain" markdown-based knowledge repo.

**Key components:**
- **Sidebar** (`src/sidebar/`) - "Brain" activity bar with week-based tree view (`brainWeekView`) for navigating daily project notes
- **Commands** (`src/commands/`) - Command palette actions like "Create Daily Project Note", "Add Frontmatter"
- **Features** (`src/features/`) - Editor enhancements (wikilink support, etc.)

**Development:**
```bash
cd packages/vscode
bun run build              # Build with esbuild (bundles core dependency)
bun run watch              # Watch mode for development
bun run package            # Create .vsix file
bin/install-vscode-extension  # Build, package, and install to code-insiders
```

**Architecture notes:**
- Uses esbuild to bundle (not tsc) — see `scripts/build.mjs`
- Bundles `@jonmagic/scripts-core` into the extension
- Targets `code-insiders` for installation
- Config setting `jonmagic.brainPath` points to the Brain repo (default: `~/Brain`)

## Agent Skills

When you identify a pattern of behavior that could be improved or standardized for AI agents working on this codebase, consider creating an **Agent Skill**.

Agent Skills are reusable instructions that help AI agents perform specific tasks consistently and correctly.

### When to Create a Skill

- Repeated workflows that need consistent execution
- Complex processes with multiple steps
- Domain-specific knowledge that agents should follow
- Patterns you find yourself explaining multiple times

### How to Create a Skill

1. Follow the Agent Skills specification at [agentskills.io](https://agentskills.io)
2. Reference the full spec at [agentconfig.org/llms-full.txt](https://agentconfig.org/llms-full.txt)
3. Create skills in the `~/code/jonmagic/skills` repository
4. Each skill should have a `SKILL.md` file with clear instructions, examples, and resources

### Skill Structure

```
skills/
  your-skill-name/
    SKILL.md           # Main skill definition
    examples/          # Example inputs/outputs (optional)
    resources/         # Supporting files (optional)
```

## Code Style

- TypeScript with strict mode
- No semicolons (enforced by ESLint)
- Use `type` imports for type-only imports
- Prefer `const` over `let`
- Use async/await over raw promises

## File Conventions

- `.gitignore` patterns: `/data*`, `/work*`, `*.vsix`, `node_modules/`, `dist/`
- Test files: `*.test.ts` (co-located with source)
- CLI entrypoints: no file extension, `#!/usr/bin/env bun` shebang
