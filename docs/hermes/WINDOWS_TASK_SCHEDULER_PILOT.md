# Windows Task Scheduler Pilot

This pilot keeps the always-on path local-first: Windows runs the scripts, GitHub gates PRs and Hermes is checked through the private SSH tunnel. It does not deploy production changes, create a scheduled task automatically, expose Hermes publicly or enable real auto-merge by default.

## Manual Command

Safe dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-hermes-nightly-pilot.ps1 `
  -UseHermesApi `
  -Json
```

Send one non-urgent phone summary:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-hermes-nightly-pilot.ps1 `
  -UseHermesApi `
  -Send `
  -Json
```

Logs are written under `.agent/nightly/<timestamp>/`.

## Task Scheduler Setup

Create the task manually in Windows Task Scheduler:

- Program: `pwsh`
- Arguments: `-NoLogo -NoProfile -ExecutionPolicy Bypass -File V:\src\skybridge-agent-hub\scripts\powershell\run-hermes-nightly-pilot.ps1 -UseHermesApi`
- Start in: `V:\src\skybridge-agent-hub`
- Trigger: daily during an operator-approved quiet window
- Run only when the user is logged on for the initial pilot

Add `-Send` only after the dry-run log is stable and the bootstrap phone path is confirmed. Do not add `-EnableAutoMerge` to the scheduled pilot until the operator has separately approved unattended low-risk merging.

## Recovery

If the task reports tunnel or Hermes health degradation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-hermes-tunnel.ps1 -Restart
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\watch-hermes-health.ps1 -Once
```

Keep all env files outside Git under `$HOME\.skybridge\`. Do not commit `.env`, Hermes keys, ntfy credentials or generated `.agent/nightly` logs.
