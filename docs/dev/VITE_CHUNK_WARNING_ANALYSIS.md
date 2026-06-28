# Vite Chunk Warning Analysis

MG366A exists to turn the remaining Vite chunk-size warning from a tracked
non-failing warning into an actionable remediation plan. It follows the warning
inventory from MG365 and the GitHub Actions Node runtime hygiene remediation
from MG366B.

This goal does not suppress the warning, raise the Vite chunk-size threshold,
change CI thresholds, upgrade dependencies, or change runtime chunking behavior.
It records the current state and defers remediation to a separate explicit goal.

## Current Status

- Warning: Vite reports chunks larger than 500 kB after minification.
- Status: non-failing, tracked, not suppressed.
- Build impact: local and CI builds complete successfully.
- Deploy impact: Deploy Cloud is not blocked by this warning.
- Policy: do not suppress warnings silently and do not raise the chunk-size
  limit in MG366A.

## Analysis Results

Current local dist output identifies two oversized JavaScript chunks:

| App | Chunk | Approx size | Observed threshold |
| --- | --- | ---: | ---: |
| web | `index-cw3dsZqf.js` | 611.53 kB | 500 kB |
| desktop | `index-BqgztAzh.js` | 602.42 kB | 500 kB |

The warning is consistent with single-entry Vite apps that bundle React,
React DOM and SkyBridge client/dashboard code into one main entry chunk.
Static inspection found no app-level dynamic imports and no `manualChunks`
strategy in the Vite configs.

Largest source contributors in the current checkout are:

- `packages/client/src/index.ts`
- `apps/desktop/src/main.tsx`
- `apps/web/src/main.tsx`
- `packages/react-widgets/src/index.tsx`

These are source-size indicators, not byte-accurate bundle attribution. A later
remediation goal should use a bundle visualizer or equivalent build analysis
before changing runtime chunking.

## Remediation Options

1. Accept the warning temporarily.
   This is acceptable while the apps are still operator/internal tools and the
   warning remains non-failing.

2. Add route-level dynamic imports.
   This can split less-used dashboard surfaces from the first-load path, but it
   changes runtime loading behavior and needs UI smoke coverage.

3. Add a `manualChunks` strategy.
   This can split React/vendor/client code from application code. It is
   straightforward but changes emitted assets and cache behavior.

4. Split dependency-heavy surfaces.
   Heavier panels or future libraries can be lazy-loaded where user workflows
   do not need them immediately.

5. Raise the chunk-size limit only with justification.
   Raising the threshold is not the default remediation and is not allowed in
   MG366A.

## Policy

- Do not suppress warnings silently.
- Do not raise `chunkSizeWarningLimit` in MG366A.
- Do not weaken CI.
- Do not change build behavior in MG366A.
- Do not change deployment behavior in MG366A.
- Remediation requires a separate goal unless a future operator explicitly
  accepts a no-runtime-risk change.

## Manual Analysis

Read-only report:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-vite-chunk-warning-analysis.ps1 -Command analyze -Json -WriteReport
```

The report is written under:

```text
.agent/tmp/vite-chunk-warning-analysis/
```

No raw build log is persisted by the analyzer. If a build summary is supplied
through `-BuildLogPath`, the script records only sanitized chunk names, sizes,
thresholds and policy flags.

## Recommended Next Milestone

- MG367A Vite Chunk Remediation if the operator wants to split the main app
  bundles.
- MG366C Hermes Planner Provider Pilot if the Vite warning is acceptable for
  now.
- MG366D Worker Service Install/Daemonization if local execution reliability
  is the next priority.

`token_printed=false`
