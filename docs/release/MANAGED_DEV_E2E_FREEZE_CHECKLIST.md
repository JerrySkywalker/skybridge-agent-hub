# Managed Dev E2E Freeze Checklist

Use this checklist before starting Hermes, MCP, managed-dev v2, or worker
service daemonization work.

- [ ] M1 Tool Provider Inventory exists:
  `scripts/powershell/skybridge-tool-provider.ps1`
- [ ] M2 Single Goal Loop exists:
  `scripts/powershell/skybridge-goal-loop.ps1`
- [ ] M3 Static Multi-Step Campaign exists:
  `scripts/powershell/skybridge-multi-goal-loop.ps1`
- [ ] M4 Local Codex Goal Markdown Generator exists:
  `scripts/powershell/skybridge-local-goal-generator.ps1`
- [ ] M5 Goal Append Review/Import exists:
  `scripts/powershell/skybridge-goal-append.ps1`
- [ ] M6 Bounded Goal Budget Loop exists:
  `scripts/powershell/skybridge-bounded-goal-loop.ps1`
- [ ] M7 Managed Development PR Pilot exists:
  `scripts/powershell/skybridge-managed-dev-pilot.ps1`
- [ ] Controller-native Git/GH provider repair exists:
  `docs/orchestrator/MANAGED_DEVELOPMENT_PR_PILOT_MG360.md`
- [ ] M8 Campaign-Driven Managed Dev E2E exists:
  `scripts/powershell/skybridge-managed-dev-campaign.ps1`
- [ ] Review/merge gate completed:
  PR #279 merged at `961b492fabdcc7a737043e83d906d6c8d3f4bf38`
- [ ] No open superseded pilot PRs remain; PR #274 is closed and not merged.
- [ ] Cloud parity is ok (`cloud parity ok`).
- [ ] `token_printed=false`

Post-freeze MG365 warning inventory:

- [ ] Warning inventory doc exists:
  `docs/dev/WARNING_INVENTORY.md`
- [ ] Warning inventory audit script exists:
  `scripts/powershell/skybridge-warning-inventory.ps1`
- [ ] Warning inventory status smoke exists:
  `smoke:warning-inventory-status`
- [ ] Warning inventory no-mutation smoke exists:
  `smoke:warning-inventory-no-mutation`
- [ ] Vite chunk-size warnings are tracked, non-failing, and not suppressed.
- [ ] GitHub Actions Node.js 20 deprecation annotations are tracked,
  non-failing, and not suppressed.
- [ ] Warning remediation is deferred to explicit future goals.

MG366B GitHub Actions Node runtime hygiene:

- [ ] Actions Node runtime hygiene doc exists:
  `docs/dev/ACTIONS_NODE_RUNTIME_HYGIENE.md`
- [ ] Actions Node runtime hygiene audit script exists:
  `scripts/powershell/skybridge-actions-node-runtime-hygiene.ps1`
- [ ] Docker action version updates are limited to Node.js 24 runtime
  candidates.
- [ ] Workflow triggers remain unchanged.
- [ ] Workflow permissions remain unchanged.
- [ ] Secrets and deploy targets remain unchanged.
- [ ] Warning suppression remains disabled.

MG366A Vite chunk warning analysis:

- [ ] Vite chunk warning analysis doc exists:
  `docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md`
- [ ] Vite chunk warning analysis script exists:
  `scripts/powershell/skybridge-vite-chunk-warning-analysis.ps1`
- [ ] Current oversized web and desktop chunks are inventoried.
- [ ] Vite chunk-size warning remains non-failing and not suppressed.
- [ ] `chunkSizeWarningLimit` remains unchanged.
- [ ] Runtime chunk-splitting remediation is deferred to a future explicit goal.

Read-only verification:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-dev-e2e-handoff.ps1 -Command audit -Json -WriteReport
```

Freeze boundary:

- [ ] No auto-merge enabled by default.
- [ ] No unbounded loop.
- [ ] No worker loop or queue runner.
- [ ] No release, tag, or asset mutation.
- [ ] No production infrastructure mutation.
- [ ] No Codex, MATLAB, Hermes, or MCP execution.
- [ ] No task creation or claim.
- [ ] No warning suppression.
- [ ] No CI threshold change.
- [ ] No build or workflow behavior change for warning remediation.
- [ ] No raw prompt/log/stdout/stderr/env/token dump.

`token_printed=false`
