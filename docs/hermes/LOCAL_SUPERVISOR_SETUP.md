# Local Hermes Supervisor Setup

Use the PowerShell bridge when Hermes or a human operator needs one bounded autonomous supervision decision.

## Dry-Run Commands

Status:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode Status `
  -DryRun `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

Start-next preview:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode StartNext `
  -DryRun `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

Repair preview:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode RepairPR `
  -DryRun `
  -PR 123 `
  -ConfigFile .\config\iteration-controller.example.json
```

Nightly report:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NightlyReport `
  -DryRun `
  -ConfigFile .\config\iteration-controller.example.json
```

Notification test:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NotifyTest `
  -DryRun
```

Operational smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-supervisor-operational.ps1 -DryRun
```

All dry-run modes return JSON, call bootstrap notification only in dry-run/no-send mode, and tolerate an offline SkyBridge API.

## Safety

Hermes supervisor dry-runs do not deploy, mutate branch protection, enable auto-merge, require real credentials or upload raw prompts/logs. Real repair or start-next modes should only be used on an AI branch with the project config reviewed.
