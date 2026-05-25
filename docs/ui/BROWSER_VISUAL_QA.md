# Browser Visual QA

Browser visual QA is deferred from v0.9 but now has an optional executable local path for environments with Playwright installed.

## Status

- Implemented: Operator Console build, static widget tests and HTTP smoke.
- Smoke-tested: fixture-backed Operator Console data, compact embed route presence through build artifacts, dashboard API data.
- Implemented when Playwright is installed: fixture-backed server/web startup, desktop/mobile console screenshots, compact embed screenshot, console-error checks, blank-page checks and simple primary-panel overlap checks.
- Implemented in CI: PR and AI-branch workflows invoke the optional smoke in skip-safe mode, upload the sanitized smoke log with existing CI logs, and upload screenshots only when a fixture-only manifest is present.
- Deferred: reliable public CI browser installation and mobile polish review.

## Intended Coverage

| Scenario | Route | Viewport | Required visible panels |
| --- | --- | ---: | --- |
| Operator Console desktop | `/` | 1440x1000 | Operator Console, Metrics Summary, Approval Queue, Notifications, Notification Matrix, Run Detail |
| Operator Console mobile | `/` | 390x900 | Operator Console, Metrics Summary, Approval Queue, Notifications, Notification Matrix, Run Detail |
| Compact embed | `/#/embed/compact` | 420x420 | SkyBridge Health |

The dashboard scenarios also run primary-panel bounding-box checks across `.skybridge-panel`, `.skybridge-card` and `.skybridge-filterbar` elements to catch obvious overlap. This is a smoke check, not a replacement for human review of the generated screenshots.

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
- writes a fixture-only `manifest.json` with the expected routes, viewport sizes, required text and local artifact safety metadata;
- fails on blank pages, missing primary panels, browser console errors or obvious primary-panel overlap.

By default, screenshots are written under `.agent/tmp/browser-visual-qa`, which is local runtime output and must not contain real agent logs or secrets. Use `-ArtifactDir <path>` to redirect artifacts for a CI upload step that is explicitly limited to fixture data.

PR and AI-branch CI run the same command without installing Playwright. In that default public-runner state the step records a skip-safe log under `.agent/ci/browser-visual-qa.log`, writes a skip manifest under `.agent/tmp/browser-visual-qa/manifest.json`, and does not produce screenshots. CI validates the manifest before uploading the artifact directory for seven days; skipped manifests must be fixture-only, non-production and marked `playwright_unavailable`, while screenshot manifests must also pass loopback-origin and PNG presence checks.

## Artifact Expectations

When Playwright is installed, the local runner should produce these screenshot files:

- `operator-console-desktop.png`
- `operator-console-mobile.png`
- `compact-embed.png`
- `manifest.json`

The manifest records the route, viewport, required text, local web origin and fixture-only safety metadata. The browser runner refuses non-loopback web bases, and the CI artifact guard checks `fixture_only`, `production_endpoint_used`, loopback origin and screenshot file presence before upload.
