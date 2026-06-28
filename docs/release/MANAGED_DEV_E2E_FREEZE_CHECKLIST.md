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
- [ ] No raw prompt/log/stdout/stderr/env/token dump.

`token_printed=false`
