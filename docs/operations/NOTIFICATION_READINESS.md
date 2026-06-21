# Notification Readiness

Goal 317 adds `skybridge-notification-readiness.ps1` for safe notification
readiness dry-runs. It checks provider status and summarizes whether blocker
notices can be supported later without sending a real message.

## Run

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-notification-readiness.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -DryRun `
  -Json
```

The output schema is `skybridge.notification_readiness.v1`.

Required safety fields:

```text
dry_run=true
real_send_performed=false
raw_notification_payload_included=false
credential_values_exposed=false
token_printed=false
```

## Policy

Goal 317 never sends a real notification. The dry-run exists so later
self-bootstrap automation can report blockers through a reviewed notification
path without exposing provider credentials, webhook URLs, raw payloads, logs,
prompts or Hermes responses.

## Smoke

```powershell
corepack pnpm smoke:notification-readiness
```

The smoke is fixture-only and proves partial readiness with no real send and no
credential or raw notification payload exposure.
