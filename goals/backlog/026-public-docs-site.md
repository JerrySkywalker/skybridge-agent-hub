# Backlog: Public Docs Site

## Background

PR #9 adds a Markdown documentation index and release docs, but no generated public docs site.

## Tasks

- Choose a docs site generator.
- Build navigation from `docs/index.md`.
- Add adapter, notifications, sidecar, approval and operations sections.
- Add CI build validation for the docs site.
- Publish only after a manual release decision.
- Add broken-link validation for repository-relative Markdown links.
- Mark release-candidate, skeleton and deferred features visibly in generated docs.

## Completion Criteria

- Docs site builds locally.
- Broken docs links fail validation.
- Public publishing is documented and gated.
- The docs site does not claim production readiness for remote execution or deployment.
- CI validates docs generation without publishing from pull requests.

## Safety Boundaries

- Do not publish automatically from public PRs.
- Do not include secrets, local databases or agent logs.
- Do not expose private URLs or production config.
- Do not include generated artifacts that leak local absolute paths.

## Validation Commands

```powershell
corepack pnpm check
corepack pnpm smoke:release-candidate
```

Add the docs build and link-check commands once the generator is selected.

## CI/CD Impact

Expected impact is a docs-build validation job and optional artifact preview. Publishing must remain manually gated and separate from public PR validation.
