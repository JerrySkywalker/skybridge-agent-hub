# SkyBridge Dogfooding Loop

SkyBridge can observe the development loop that builds SkyBridge.

## Safe Loop

```text
Codex hook smoke
Codex exec or runner smoke
Dogfooding fixture events
        |
        v
POST /v1/events
        |
        v
Dashboard, run detail, metrics, notification jobs
```

Run the smoke against a local server:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-dogfooding-loop.ps1 `
  -ApiBase http://127.0.0.1:8787
```

The script emits only fixture metadata with `category = dogfooding`. It does not install real hooks, read secrets, upload prompts or execute remote commands.
