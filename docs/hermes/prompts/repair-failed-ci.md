# Hermes Prompt: Repair Failed CI

Repair one PR through the CI Guardian. Do not hand-edit GitHub settings.

Command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode RepairPR `
  -DryRun `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

Replace `-DryRun` with a real repair only after confirming the PR is an AI branch and the failure does not require secrets, production deployment or privileged runners.

Safety:
- use `notify-bootstrap.ps1` for repeated failure or safety boundary messages;
- do not remove tests to pass;
- do not force-push `main`;
- do not upload raw CI logs to SkyBridge.
