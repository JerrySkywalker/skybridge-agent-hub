# Bootstrap Notifications

SkyBridge's own development automation cannot assume the SkyBridge Notification Center is online. Controller, CI Guardian and Hermes supervisor scripts must have a direct phone-notification path for critical lifecycle messages.

`scripts/powershell/notify-bootstrap.ps1` is that path. It sends directly to ntfy using environment variables, and it can also send urgent messages to a WeCom/WeChat webhook. It does not call the SkyBridge server.

## Environment Variables

ntfy options:

- `NTFY_TOPIC_URL`: full topic URL, for example `https://ntfy.sh/example-topic`.
- or `NTFY_URL` plus `NTFY_TOPIC`.
- optional `NTFY_TOKEN`.
- optional `NTFY_USER` and `NTFY_PASSWORD` when token auth is not used.

WeCom/WeChat option:

- `WECOM_WEBHOOK_URL`: used only for `urgent` severity.

Do not commit real values. Keep them in the local shell, OS secret store or CI secret store.

## Severities

- `info`: direct ntfy default-priority lifecycle notice.
- `warning`: direct ntfy high-priority retry or degraded-state notice.
- `urgent`: direct ntfy urgent notice plus optional WeCom/WeChat webhook.

## Migration Stages

Stage 1, bootstrap direct notification:
Automation calls `notify-bootstrap.ps1` directly for important lifecycle messages. This works even when SkyBridge is offline.

Stage 2, dual-write:
Automation calls `notify-bootstrap.ps1` for phone delivery and also emits safe SkyBridge iteration events when the server is reachable. SkyBridge event delivery is fail-open.

Stage 3, SkyBridge primary with bootstrap fallback:
After the Notification Center is production-ready for SkyBridge's own operations, automation may request notifications through SkyBridge first. The bootstrap notifier remains the fallback for server outage, safety-boundary and repeated-failure alerts.

## Smoke

Dry-run smoke does not require notification credentials and does not send messages:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-bootstrap-notification.ps1
```

Manual dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge" `
  -Message "Controller dry run" `
  -Severity warning `
  -DryRun `
  -Json
```
