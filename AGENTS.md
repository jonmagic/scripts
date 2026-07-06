# Scripts Agent Guide

These instructions apply to the whole repository unless a deeper `AGENTS.md` overrides them. The closest `AGENTS.md` wins.

## Mission

`jonmagic/scripts` is @jonmagic's owned automation surface for Brain workflows, local CLI helpers, VS Code Insiders extension work, and Raycast actions. The project should make repeated Brain mechanics deterministic while preserving useful human judgment.

## Start Here

1. Read `README.md`, this file, and the nearest package README before making changes.
2. Check `git status --short` and preserve user edits.
3. Use project skills in `.github/skills/` when the task matches one.
4. For Brain extension work, read `packages/vscode/package.json`, `packages/vscode/README.md`, and `packages/vscode/src/extension.ts`.
5. Work directly on `main` for this repo unless @jonmagic or a repository rule explicitly asks for a branch.

## Non-negotiables

1. Use Bun only. Never use npm, yarn, or pnpm, and never create non-Bun lockfiles.
2. Preserve user edits. Never reset, checkout, or overwrite dirty files unless explicitly asked.
3. Do not estimate timelines unless @jonmagic explicitly asks.
4. Use red-green-refactor wherever practical.
5. Keep docs close to behavior and update them with behavior, command, or workflow changes.
6. Prefer quality over speed. Use critical review for meaningful security, privacy, data-handling, architecture, production, or product-risk consequences.
7. Commit completed logical units with semantic commits when asked to finish changes.
8. Follow the repository style: TypeScript strict mode, no semicolons, type-only imports for type-only values, `const` over `let` when possible, and async/await over raw promise chains.
9. Use semantic commit messages with package scopes when applicable, for example `feat(vscode): add recent Brain quick pick`.

## Development Harness

Use these commands from the repository root unless a package-specific task needs a narrower command:

```bash
bun install
bun run typecheck
bun run lint
bun test
bun run build
```

Targeted commands:

```bash
bun test packages/vscode/test/gitignore.test.ts
cd packages/vscode && bun run typecheck
cd packages/vscode && bun run build
cd packages/vscode && bun run package
bin/install-vscode-extension
```

Before committing code changes, run the closest validation that covers the change. For broad package changes, use:

```bash
bun run typecheck && bun run lint && bun test && bun run build
```

There is not yet a VS Code extension-host test runner in this repo. Bun tests can cover pure logic and fixtures, but they do not prove runtime TreeView, command execution, menu enablement, activation, or editor integration behavior. If runtime UI coverage is needed, first design the smallest safe harness and apply the dependency-safety gate before adding packages such as VS Code extension test tooling.

## Adding CLI Commands

1. Create the implementation in `packages/cli/src/<command>.ts`.
2. Export it from `packages/cli/src/index.ts`.
3. Create an extensionless entrypoint in `packages/cli/bin/<command>`.
4. Start entrypoints with `#!/usr/bin/env bun`.
5. Import implementation from `../src/<command>.js`; Bun resolves the TypeScript source.
6. Use `node:util` `parseArgs` for argument parsing.
7. Make the entrypoint executable with `chmod +x packages/cli/bin/<command>`.
8. Add the command to `bin` in `packages/cli/package.json`.

## File Conventions

- Test files are co-located `*.test.ts` files.
- CLI entrypoints have no file extension.
- `bun.lock` is the only allowed package-manager lockfile.
- Generated VS Code packages (`*.vsix`), `dist/`, `*.tsbuildinfo`, `node_modules/`, `/data*`, and `/work*` stay out of commits unless a future task explicitly changes that convention.

## Architecture and Boundaries

- `packages/core` contains shared deterministic Brain utilities: frontmatter, TIDs, wikilinks, note/bookmark helpers, and session detection.
- `packages/cli` contains command-line tools and Brain helpers.
- `packages/vscode` contains the VS Code Insiders extension. It bundles `@jonmagic/scripts-core` with esbuild and installs to `code-insiders`.
- `packages/raycast` contains Raycast actions.
- The VS Code extension's canonical Brain root comes from `jonmagic.brainPath`, defaulting to `~/Brain`.
- Brain writes should be typed and deterministic. Prefer explicit actions such as creating a Daily Project, appending a Weekly Note TODO, or adding a Project reference over generic "save to Brain" flows.
- Treat AI classification, summarization, or routing as untrusted. Use structured contracts, validate paths and output types, then perform deterministic file writes.
- Treat unbounded persisted state for staleable data as an agent miss. Any saved UI state, cache, index, history, or derived state that can go stale needs a bounded lifecycle such as TTL, caps, pruning, invalidation, or an explicit reason it is finite.

## VS Code Extension UX Harness

Agents working on `packages/vscode` are responsible for testing UX without relying on @jonmagic to manually discover breakage.

1. Prefer automated checks first where they actually cover behavior: targeted Bun tests for pure logic, package typecheck, extension build, and package build.
2. For UI behavior, create the smallest reproducible Brain fixture or use the configured local Brain only when necessary.
3. Use static VS Code contribution checks where possible: verify contributed command IDs, menu registrations, activation events, view IDs, and configuration keys in `packages/vscode/package.json` match registrations in `src/extension.ts`.
4. Validate user-visible flows against the built extension, not only TypeScript types. Runtime TreeView, command execution, menu enablement, activation, and editor behavior need an installed-extension smoke check or a future extension-host test harness.
5. Install unreviewed builds into an isolated VS Code Insiders profile or extension directory for smoke checks. Before finishing any user-visible VS Code extension change, run `bin/install-vscode-extension` from the repository root, confirm `code-insiders --list-extensions` includes `jonmagic.jonmagic-scripts`, then restart or reload VS Code Insiders so the updated extension activates, unless @jonmagic explicitly asks not to install or restart it. The isolated install is useful evidence, but it is not a substitute for the project install script and activation restart.
6. If a UI change cannot be fully automated, capture concrete evidence: command output, macOS screenshot, accessible tree/text output, or a short reproduction artifact.
7. Do not ask @jonmagic to test routine navigation, build, packaging, or visual smoke checks. Ask only for product judgment, credentials, or a choice that cannot be inferred from the repo.

## ZShot Visual Harness

Use ZShot when browser-backed or rendered captures would improve confidence for docs, HTML output, webviews, state debugging, or agent-readable snapshots. On @jonmagic's Mac, the bundled CLI is usually available at `~/Library/Application Support/ZShot/zshot`.

ZShot is URL/browser-backed. It does not capture VS Code TreeViews or the activity bar. For editor UI evidence, use an isolated VS Code Insiders profile plus native screenshots or accessible output instead.

Discover capabilities with:

```bash
"$HOME/Library/Application Support/ZShot/zshot" --agent-help
"$HOME/Library/Application Support/ZShot/zshot" --help
"$HOME/Library/Application Support/ZShot/zshot" --help all
```

Recommended defaults:

1. Capture rendered HTML for low-friction smoke checks: `zshot -t html -f <artifact>.html <url>`.
2. Use screenshots, PDF, HAR, WARC, Markdown, AXTree, trace, or pprof only when the local license supports the output type.
3. Keep generated ZShot artifacts out of commits unless they are intentional fixtures or documentation assets.
4. Do not send secrets, private app data, or sensitive URLs through third-party services for capture.

## Agent Workflow

- Make focused, reviewable changes.
- Search for existing helpers before adding new ones.
- Keep fuzzy AI decisions separate from deterministic actions. Validate before writing files, posting messages, installing extensions, or changing repo state.
- Use direct tools for bounded search, reads, small edits, and formatting.
- Add or update project skills only when repeated workflows justify routing-friendly guidance.
- Rubber-duck high-stakes or ambiguous work before treating the direction as settled, especially around security, privacy, data handling, external services, persistence, deployment, permissions, or broad architecture.
- If an agent miss reveals a durable gap, improve the harness with the smallest useful artifact: instructions, docs, scripts, tests, or guardrails.
- Leave the repo easier for the next agent by capturing newly discovered commands, constraints, validation steps, and gotchas here or in a focused project skill.

## Task Exit Criteria

1. The closest available validation passes.
2. Behavior is verified automatically or with concrete UX evidence.
3. Documentation is updated when commands, behavior, workflow, or constraints change.
4. User-visible VS Code extension changes have been installed with `bin/install-vscode-extension`, confirmed in VS Code Insiders, and followed by a VS Code Insiders restart or reload, unless explicitly skipped.
5. Handoff names changed files and any remaining risks.
