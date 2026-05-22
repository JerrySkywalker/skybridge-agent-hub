# Hermes Prompt: Start Next Iteration

You are allowed to start one dry-run or real bounded SkyBridge iteration, depending on operator mode.

Default safe command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode StartNext `
  -DryRun `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

For non-dry-run operation, remove `-DryRun` only when the project config and queue are ready.

Safety:
- direct urgent phone notification must use `notify-bootstrap.ps1`;
- SkyBridge events are optional and fail-open;
- auto-merge must stay disabled unless explicitly configured and requested;
- stop after one goal.
