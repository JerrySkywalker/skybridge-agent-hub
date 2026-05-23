# Bootstrap Phone Setup On Windows

Bootstrap notifications are the direct phone fallback for Codex, CI Guardian and Hermes supervision. They do not require the SkyBridge server.

## Phone Setup

1. Install an ntfy-compatible phone app.
2. Subscribe to your normal SkyBridge bootstrap topic.
3. Subscribe to a separate urgent topic if you want loud escalation.
4. Allow notification permission for the app.
5. Disable battery optimization for the app so urgent messages are not delayed.
6. Keep topic names private and do not paste them into Git-tracked files.

## Local Shell Setup

Set environment variables in a local PowerShell profile, Windows user environment, or a secret manager. Do not write real values to this repository.

```powershell
$env:SKYBRIDGE_BOOTSTRAP_NTFY_URL = "https://ntfy.example.invalid"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC = "example-topic"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC = "example-urgent-topic"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN = ""
$env:SKYBRIDGE_BOOTSTRAP_NTFY_USER = ""
$env:SKYBRIDGE_BOOTSTRAP_NTFY_PASS = ""
$env:SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK = ""
```

Use either token auth or user/password auth, not both.

## Verification

No-send JSON check:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge bootstrap" `
  -Message "Windows setup dry run" `
  -Severity warning `
  -Json
```

Smoke test:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-bootstrap-notification.ps1 -DryRun
```

Explicit real send:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge bootstrap" `
  -Message "Explicit Windows send test" `
  -Severity urgent `
  -Send `
  -Json
```

The script reports skipped status when config is missing and configured status when config exists but `-Send` is omitted.
