# Copilot Instructions for jonmagic/scripts

## Overview

This is a TypeScript monorepo for personal automation tools. It uses **Bun** exclusively as the package manager and runtime.

## Critical Rules

### Bun Only - No npm/yarn/pnpm

- **ALWAYS** use `bun` commands, never `npm`, `yarn`, or `pnpm`
- **NEVER** create or commit `package-lock.json`, `yarn.lock`, or `pnpm-lock.yaml`
- The only lock file should be `bun.lock`
- Use `bun install`, `bun run`, `bun test`, `bun tsc`, etc.

### Development Workflow

```bash
# Install dependencies
bun install

# Build all packages
bun run build

# Run tests
bun test

# Lint
bun run lint

# Type check
bun run typecheck
```

### Before Committing

Always run these checks before committing changes:

```bash
bun install          # Ensure dependencies are up to date
bun run typecheck    # Verify no TypeScript errors
bun run lint         # Verify no linting errors
bun test             # Verify tests pass
bun run build        # Verify build succeeds
```

### Package Structure

- `packages/core` - Shared TypeScript utilities (`@jonmagic/scripts-core`)
- `packages/cli` - CLI tools (`@jonmagic/scripts-cli`)
- `packages/vscode` - VS Code extension
- `packages/raycast` - Raycast extension

### Adding New CLI Commands

1. Create implementation in `packages/cli/src/your-command.ts`
2. Export from `packages/cli/src/index.ts`
3. Create CLI entrypoint in `packages/cli/bin/your-command` with `#!/usr/bin/env bun` shebang
4. Make executable: `chmod +x packages/cli/bin/your-command`
5. Import from `../src/your-command.js` (bun handles .ts resolution)

### VS Code Extension

```bash
# Build and install
bin/install-vscode-extension

# Package only
cd packages/vscode && bun run package
```

Uses `code-insiders` for installation.

### Raycast Extension

```bash
# Install/link for development
bin/install-raycast-extension

# Or manually
cd packages/raycast && ray develop
```

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
