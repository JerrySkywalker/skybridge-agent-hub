# Backlog: Real Browser Visual QA

## Background

PR #9 validates the dashboard with React static rendering, Vite builds and HTTP smoke scripts, but it does not capture real browser screenshots. This is safe to defer because it does not affect server correctness, but it is required before treating v0.9 UI polish as release-ready.

## Tasks

- Add Playwright or the Codex Browser plugin smoke for the Operator Console.
- Capture desktop and mobile screenshots for the main console and compact embed.
- Verify the approval queue, metrics summary and provider matrix panels render without overlap.
- Add a CI-safe fallback path when browser automation is unavailable.
- Store screenshots as short-lived CI artifacts only when they use fixture data.
- Document the viewport matrix and the expected visible panels for each route.

## Completion Criteria

- Screenshot artifacts are produced locally or in CI for review.
- Browser smoke fails on blank page, console errors or missing primary panels.
- Documentation explains how to run visual QA locally.
- The smoke uses generated demo events or a temporary SQLite database, not real agent logs.
- The check is wired into PR CI only if it remains reliable on GitHub-hosted runners.

## Safety Boundaries

- Do not use production endpoints.
- Do not capture secrets, local private paths or real agent output.
- Do not require privileged self-hosted runners for public PRs.

## Validation Commands

```powershell
corepack pnpm --filter @skybridge-agent-hub/web build
corepack pnpm smoke:operator-console
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\validate-powershell.ps1
```

Add the final browser command here when the implementation chooses Playwright or the Codex Browser plugin.

## CI/CD Impact

Expected impact is a new artifact-producing visual smoke job for PR and AI-branch validation. It must remain optional or fixture-only until its flake rate is known, and it must never require production endpoints or self-hosted runners.
