# Browser Visual QA

Browser visual QA is deferred from v0.9 but now has an optional executable local path for environments with Playwright installed.

## Status

- Implemented: Operator Console build, static widget tests and HTTP smoke.
- Smoke-tested: fixture-backed Operator Console data, compact embed route presence through build artifacts, dashboard API data.
- Implemented when Playwright is installed: fixture-backed server/web startup, desktop/mobile console screenshots, compact embed screenshot, console-error checks, blank-page checks and simple primary-panel overlap checks.
- Deferred: reliable public CI browser installation, artifact upload workflow and mobile polish review.

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

## Current Runner

```powershell
corepack pnpm --filter @skybridge-agent-hub/web build
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-browser-visual-qa.ps1 -SkipWhenUnavailable
```

The runner intentionally skips when Playwright is unavailable. When Playwright is available under `node_modules`, the script:

- starts a temporary SQLite-backed SkyBridge server;
- seeds generated demo events;
- starts a local Vite preview pointed at that temporary API;
- captures screenshots for the Operator Console desktop viewport, Operator Console mobile viewport and compact embed route;
- fails on blank pages, missing primary panels, browser console errors or obvious primary-panel overlap.

By default, screenshots are written under `.agent/tmp/browser-visual-qa`, which is local runtime output and must not contain real agent logs or secrets. Use `-ArtifactDir <path>` to redirect artifacts for a CI upload step that is explicitly limited to fixture data.
