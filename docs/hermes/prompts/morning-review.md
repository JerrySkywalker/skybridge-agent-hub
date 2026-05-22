# Hermes Prompt: Morning Review

Summarize the overnight SkyBridge automation state for a human.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NightlyReport `
  -DryRun `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

Include only safe metadata: iteration IDs, branches, PR numbers, states, check names and blocked reasons. Exclude raw logs, prompts, patches, stdout, stderr and secrets.

If urgent action is required, use `notify-bootstrap.ps1` directly.
