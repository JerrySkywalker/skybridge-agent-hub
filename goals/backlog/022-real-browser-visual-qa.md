# Backlog: Real Browser Visual QA

## Background

PR #9 validates the dashboard with React static rendering, Vite builds and HTTP smoke scripts, but it does not capture real browser screenshots. This is safe to defer because it does not affect server correctness, but it is required before treating v0.9 UI polish as release-ready.

## Tasks

- Add Playwright or the Codex Browser plugin smoke for the Operator Console. Initial optional Playwright runner exists in `scripts/browser-visual-qa.mjs`.
- Capture desktop and mobile screenshots for the main console and compact embed. Local optional artifacts are written by `scripts/powershell/smoke-browser-visual-qa.ps1` when Playwright is installed.
- Verify the approval queue, metrics summary and provider matrix panels render without overlap. Initial panel presence and bounding-box overlap checks exist; manual visual review and CI artifact review remain pending.
- Add a CI-safe fallback path when browser automation is unavailable.
- Store screenshots as short-lived CI artifacts only when they use fixture data.
- [x] Document the viewport matrix and the expected visible panels for each route.
- [x] Add an artifact manifest beside screenshots before CI upload is enabled.
- [x] Invoke the optional browser visual QA smoke from PR and AI-branch CI in skip-safe mode.

## Completion Criteria

- Screenshot artifacts and a fixture-only `manifest.json` are produced locally or in CI for review. Local artifact generation is implemented when Playwright is installed; CI invokes the skip-safe runner and uploads its sanitized log, while screenshot upload remains pending.
- Browser smoke fails on blank page, console errors or missing primary panels. Initial local checks are implemented.
- Documentation explains how to run visual QA locally and identifies the expected desktop, mobile and compact embed screenshot matrix. Initial local runner documentation exists in `docs/ui/BROWSER_VISUAL_QA.md`.
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
corepack pnpm smoke:browser-visual-qa
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\validate-powershell.ps1
```

The default `smoke:browser-visual-qa` command skips successfully when Playwright is unavailable. Install Playwright in a controlled local/CI environment to produce screenshots from fixture data.

## CI/CD Impact

Expected impact is a new artifact-producing visual smoke job for PR and AI-branch validation. It must remain optional or fixture-only until its flake rate is known, and it must never require production endpoints or self-hosted runners.
