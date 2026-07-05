# VS Code Extension Development

Use this skill for `packages/vscode` work in `jonmagic/scripts`: Brain sidebar navigation, command palette actions, wikilinks, VS Code contributions, extension packaging, and UX validation.

Do not use this skill for unrelated CLI, Raycast, or core-library-only tasks unless the change affects the VS Code extension.

## Workflow

1. Read `AGENTS.md`, `packages/vscode/package.json`, and the files for the feature being changed.
2. Identify whether the change affects contributions, activation, command registration, filesystem reads, Brain writes, or user-visible tree/menu behavior.
3. Keep AI judgment advisory. Deterministic code must perform command registration, file writes, path resolution, and package changes.
4. Validate all contributed command IDs and view IDs across `package.json` and `src/extension.ts`.
5. Prefer targeted checks first, then escalate only when the change requires it.
6. Remember that this repo does not yet have a VS Code extension-host test runner. Bun tests are useful for pure logic, not runtime editor UI.

## Common Commands

```bash
cd packages/vscode && bun run typecheck
cd packages/vscode && bun run build
bun test packages/vscode/test/gitignore.test.ts
cd packages/vscode && bun run package
bin/install-vscode-extension
```

Use root-level checks for cross-package changes:

```bash
bun run typecheck && bun run lint && bun test && bun run build
```

## UX Testing Contract

Agents should not rely on @jonmagic for routine extension testing.

For each user-visible change, provide one of:

1. an automated test that exercises the behavior,
2. a package/type/build validation plus command/menu contribution verification,
3. an installed-extension smoke check in an isolated VS Code Insiders profile or extension directory,
4. a concrete artifact such as a macOS screenshot, accessible text/tree output, or reproduction fixture.

If none of these is possible, state exactly why and keep the change advisory or behind a human decision gate.

Do not claim runtime TreeView, activation, menu, or command behavior is fully automated unless an extension-host harness has been added. If that harness is needed, apply the dependency-safety workflow before adding any VS Code test packages.

## Brain Safety

- Default Brain path is `~/Brain`, but tests that write must use temp fixtures.
- Do not write to real Brain content during tests unless the user explicitly asks.
- Brain writes must be typed actions, not generic saves.
- Validate paths stay inside the configured Brain root before reading, copying, renaming, deleting, or writing.
- Do not add unbounded persisted state for data that can go stale. Saved UI state, caches, indexes, histories, and derived state need TTL, caps, pruning, invalidation, or a clearly finite keyspace.

## Useful Product Direction

- Do not turn the left Brain sidebar into a giant Explorer replacement.
- Prefer recent-first, focused surfaces.
- Use quick-pick commands for broad navigation.
- Keep tree views lazy, collapsed, and contextual.
- Right-side or auxiliary-bar surfaces are appropriate for related files, backlinks, references, and active context.

## Exit Criteria

1. Targeted validation passed for the changed behavior.
2. UX behavior has concrete evidence beyond "it compiles" when the user can see or click it.
3. README, package contributions, and this skill are updated if workflow or commands changed.
4. Any new persisted/cached state has a bounded lifecycle, or the finite scope is documented in the implementation or tests.
