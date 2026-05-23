# Server Hermes Supervisor Setup

Server-side Hermes supervision should run one bounded bridge invocation per schedule tick. It should not run an unbounded loop inside the script.

## Recommended Schedule

- hourly `Status` dry-run for health and notification path validation;
- nightly `NightlyReport` dry-run for summary;
- operator-approved `StartNext` or `RepairPR` when queue and PR safety conditions are met.

## Commands

Offline-safe status:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode Status `
  -DryRun `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

Operational smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-supervisor-operational.ps1 -DryRun
```

Bootstrap notification test:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NotifyTest `
  -DryRun
```

## Server Environment

Configure bootstrap phone notification with `SKYBRIDGE_BOOTSTRAP_*` variables outside Git. See `docs/notifications/BOOTSTRAP_SETUP_SERVER.md`.

The supervisor bridge does not require SkyBridge Notification Center for phone alerts and does not require the SkyBridge server for safe dry-run output.

## Boundaries

Do not schedule server-side commands that:

- deploy to production;
- mutate branch protection;
- enable auto-merge without manual GitHub setup;
- require production secrets;
- run privileged self-hosted public PR jobs;
- execute remote WSS commands.

Real `StartNext` and `RepairPR` invocations should be logged locally and reviewed like other autonomous iteration runs.
