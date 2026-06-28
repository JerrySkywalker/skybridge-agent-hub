# Warning Inventory

Inventory date: 2026-06-29

This inventory tracks known non-failing warnings separately from remediation.
It is a managed-dev v2 low-risk task artifact, not a warning fix.

## Known Warnings

### Vite Chunk-Size Warning

- Category: Vite chunk-size warning.
- Status: non-failing, tracked, not suppressed.
- Current impact: does not block the MG351-MG364 managed-dev baseline.
- Deploy impact: does not block Deploy Cloud.
- Policy: do not suppress silently and do not change chunk thresholds without a
  future explicit goal.

### GitHub Actions Node.js 20 Deprecation Annotation

- Category: GitHub Actions Node.js 20 deprecation annotation for Docker actions.
- Status: non-failing, tracked, not suppressed.
- Current impact: does not block the MG351-MG364 managed-dev baseline.
- Deploy impact: does not block Deploy Cloud.
- Policy: do not change workflow behavior without a future explicit goal.

## Remediation Policy

- Future goal required before changing build or workflow behavior.
- No silent warning suppression.
- No CI threshold changes without an explicit goal.
- No Vite config changes in this inventory goal.
- No GitHub workflow changes in this inventory goal.
- No deploy configuration changes in this inventory goal.

## Follow-Up Backlog

- MG366A: Vite Chunk Warning Analysis.
- MG366B: GitHub Actions Node Runtime Hygiene.
- MG366C: Hermes Planner Provider Pilot.

`token_printed=false`
