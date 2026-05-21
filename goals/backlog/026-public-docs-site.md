# Backlog: Public Docs Site

## Background

PR #9 adds a Markdown documentation index and release docs, but no generated public docs site.

## Tasks

- Choose a docs site generator.
- Build navigation from `docs/index.md`.
- Add adapter, notifications, sidecar, approval and operations sections.
- Add CI build validation for the docs site.
- Publish only after a manual release decision.

## Completion Criteria

- Docs site builds locally.
- Broken docs links fail validation.
- Public publishing is documented and gated.

## Safety Boundaries

- Do not publish automatically from public PRs.
- Do not include secrets, local databases or agent logs.
- Do not expose private URLs or production config.
