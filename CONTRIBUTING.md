# Contributing to Scripts

## Development Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/jonmagic/scripts.git
   cd scripts
   ```

2. Run setup:
   ```bash
   bin/setup
   ```

## Project Structure

This is a Bun monorepo with the following packages:

- `packages/core` - Shared TypeScript utilities (`@jonmagic/scripts-core`)
- `packages/cli` - CLI tools (`@jonmagic/scripts-cli`)
- `packages/vscode` - VS Code extension
- `packages/raycast` - Raycast extension

## Development Commands

```bash
# Install dependencies
bun install

# Build all packages
bun run build

# Build individual packages
bun run build:core
bun run build:cli
bun run build:vscode

# Run tests
bun test

# Lint
bun run lint

# Type check
bun run typecheck
```

## Adding a New CLI Command

1. Create the implementation in `packages/cli/src/your-command.ts`
2. Export it from `packages/cli/src/index.ts`
3. Create the CLI entrypoint in `packages/cli/bin/your-command`
4. Make it executable: `chmod +x packages/cli/bin/your-command`

## Code Style

- TypeScript with strict mode
- No semicolons (enforced by ESLint)
- Use `type` imports for type-only imports

## Releasing

This repo doesn't publish to npm. Extensions are installed locally:

- VS Code: `bin/install-vscode-extension`
- Raycast: `bin/install-raycast-extension`
