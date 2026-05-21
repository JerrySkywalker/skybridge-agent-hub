# Browser Visual QA

Browser visual QA is deferred from v0.9 but scaffolded for the next safe UI hardening pass.

## Status

- Implemented: Operator Console build, static widget tests and HTTP smoke.
- Smoke-tested: fixture-backed Operator Console data, compact embed route presence through build artifacts, dashboard API data.
- Deferred: real browser screenshots, console-error capture, mobile viewport review and artifact upload.

## Intended Coverage

- Operator Console desktop viewport.
- Operator Console mobile viewport.
- Compact embed route at `/#/embed/compact`.
- Approval queue, metrics summary, notification provider matrix and run detail panels.

## Safety Rules

- Use temporary SQLite databases and generated demo events only.
- Do not point browser automation at production endpoints.
- Do not capture real agent output, prompts, patches, private paths, tokens, cookies or screenshots of secret-bearing pages.
- Public PR CI may upload screenshots only when they are generated from fixture data on GitHub-hosted runners.

## Current Scaffold

```powershell
corepack pnpm --filter @skybridge-agent-hub/web build
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-browser-visual-qa.ps1 -SkipWhenUnavailable
```

The scaffold intentionally skips when Playwright is unavailable. A future implementation should add a local browser test runner, start temporary fixture-backed server and web processes, fail on blank pages or console errors, and write short-lived screenshot artifacts.
