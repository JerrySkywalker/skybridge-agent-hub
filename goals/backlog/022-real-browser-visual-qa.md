# Backlog: Real Browser Visual QA

## Background

PR #9 validates the dashboard with React static rendering, Vite builds and HTTP smoke scripts, but it does not capture real browser screenshots. This is safe to defer because it does not affect server correctness, but it is required before treating v0.9 UI polish as release-ready.

## Tasks

- Add Playwright or the Codex Browser plugin smoke for the Operator Console.
- Capture desktop and mobile screenshots for the main console and compact embed.
- Verify the approval queue, metrics summary and provider matrix panels render without overlap.
- Add a CI-safe fallback path when browser automation is unavailable.

## Completion Criteria

- Screenshot artifacts are produced locally or in CI for review.
- Browser smoke fails on blank page, console errors or missing primary panels.
- Documentation explains how to run visual QA locally.

## Safety Boundaries

- Do not use production endpoints.
- Do not capture secrets, local private paths or real agent output.
- Do not require privileged self-hosted runners for public PRs.
