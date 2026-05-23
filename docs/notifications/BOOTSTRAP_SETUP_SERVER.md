# Bootstrap Phone Setup On A Server

Use bootstrap notifications for local or server-side supervision before the SkyBridge Notification Center is trusted for SkyBridge's own alerts.

## Server Environment

Store real values outside Git, for example in a service environment file or a secret manager managed by the operator.

```text
SKYBRIDGE_BOOTSTRAP_NTFY_URL=https://ntfy.example.invalid
SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC=example-topic
SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC=example-urgent-topic
SKYBRIDGE_BOOTSTRAP_NTFY_USER=
SKYBRIDGE_BOOTSTRAP_NTFY_PASS=
SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN=
SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK=
```

Do not store these values in `.env` files that could be committed. Do not add production notification topics or webhook URLs to docs, goals, PR descriptions or CI logs.

## Phone Setup

- Subscribe the phone app to the normal topic.
- Subscribe to the urgent topic if used.
- Enable notification permission.
- Disable app battery optimization.
- Test normal and urgent topics after setting the server environment.

## Safe Verification

Dry-run/no-send:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge server bootstrap" `
  -Message "Server dry run" `
  -Severity warning `
  -Json
```

Smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-bootstrap-notification.ps1 -DryRun
```

Real send requires an explicit operator command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge server bootstrap" `
  -Message "Explicit server send test" `
  -Severity urgent `
  -Send `
  -Json
```

This setup does not deploy SkyBridge, does not depend on the SkyBridge API, and does not grant remote execution.
