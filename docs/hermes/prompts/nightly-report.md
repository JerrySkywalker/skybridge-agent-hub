# Hermes Prompt: Nightly Report

Prepare a nightly autonomous iteration report.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NightlyReport `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

Report:
- active iteration;
- open PR or CI state;
- repair attempts;
- blocked reasons;
- whether direct bootstrap notification was needed;
- next safe action.

Do not deploy or change remote settings.
