# Hermes Prompt: Summarize Blocked Run

Create a blocked-run summary for the human operator.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode Status `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

If the JSON shows `blocked`, `failed`, `urgent` or a safety boundary, call:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge blocked" `
  -Message "<short blocked reason>" `
  -Severity urgent
```

Do not include raw prompts, patches, stdout, stderr, tokens or secrets in the summary.
