# Bootstrap Notifications

SkyBridge's own development automation cannot assume the SkyBridge Notification Center is online. Controller, CI Guardian and Hermes supervisor scripts must have a direct phone-notification path for critical lifecycle messages.

`scripts/powershell/notify-bootstrap.ps1` is that direct fallback path. It sends directly to ntfy using environment variables, and it can also send urgent messages to a WeCom/WeChat webhook. It does not call the SkyBridge server.

For current self-bootstrap readiness, the required administrator escalation path is cloud Hermes WeChat or WeCom. The bootstrap notifier remains the fallback interface. SkyBridge Notification Center providers and Jerry's future custom notify gateway are long-term primary paths, but skipped native providers are not the immediate self-bootstrap blocker when Hermes administrator escalation is ready.

## Environment Variables

Preferred SkyBridge bootstrap ntfy options:

- `SKYBRIDGE_BOOTSTRAP_NTFY_URL`: ntfy server base URL, for example `https://ntfy.sh`.
- `SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC`: normal-priority topic.
- `SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC`: optional urgent topic used for `urgent` severity.
- `SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN`: optional token auth.
- `SKYBRIDGE_BOOTSTRAP_NTFY_USER` and `SKYBRIDGE_BOOTSTRAP_NTFY_PASS`: optional basic auth when token auth is not used.

WeCom/WeChat option:

- `SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK`: optional urgent-only webhook.

Do not commit real values. Keep them in the local shell, OS secret store or CI secret store.

Legacy variables remain supported for local compatibility: `NTFY_TOPIC_URL`, `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN`, `NTFY_USER`, `NTFY_PASSWORD` and `WECOM_WEBHOOK_URL`.

## Severities

- `info`: direct ntfy default-priority lifecycle notice.
- `warning`: direct ntfy high-priority retry or degraded-state notice.
- `urgent`: direct ntfy urgent notice plus optional WeCom/WeChat webhook.

## Migration Stages

Stage 1, bootstrap direct notification:
Automation uses cloud Hermes WeChat or WeCom for current bootstrap administrator escalation. `notify-bootstrap.ps1` remains available as the direct fallback for important lifecycle messages and works even when SkyBridge is offline.

Stage 2, dual-write:
Automation calls `notify-bootstrap.ps1` for phone delivery and also emits safe SkyBridge iteration events when the server is reachable. SkyBridge event delivery is fail-open.

Stage 3, SkyBridge primary with bootstrap fallback:
After the Notification Center is production-ready for SkyBridge's own operations, automation may request notifications through SkyBridge first. The bootstrap notifier remains the fallback for server outage, safety-boundary and repeated-failure alerts.

Readiness should block on `admin_escalation_unavailable` when the current Hermes WeChat or WeCom channel cannot send blocker notices. It should only warn with `skybridge_notification_center_not_ready` when Hermes admin escalation is ready but native SkyBridge providers are skipped.

## Smoke

Dry-run smoke does not require notification credentials and does not send messages:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-bootstrap-notification.ps1
```

The Operator Console notification view is available at `http://127.0.0.1:3000/#/notifications` after starting the local web app. It shows provider status, sent/skipped/failed counts and the bootstrap fallback path without exposing credential values.

Manual dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge" `
  -Message "Controller dry run" `
  -Severity warning `
  -DryRun `
  -Json
```

Configured dry run without sending:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge" `
  -Message "Configured no-send check" `
  -Severity warning `
  -Json
```

Real delivery requires `-Send` and configured environment variables:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge" `
  -Message "Explicit bootstrap send" `
  -Severity urgent `
  -Send `
  -Json
```

See `docs/notifications/BOOTSTRAP_SETUP_WINDOWS.md` and `docs/notifications/BOOTSTRAP_SETUP_SERVER.md` for operator setup.

Default readiness probes and smokes must not send a real message. Outputs must not contain credential values, raw Hermes responses, raw prompts, raw logs, raw notification payloads, webhooks, tokens, cookies, private keys, auth headers or production config values. Safety fields such as `token_printed=false`, `credential_values_exposed=false`, `raw_response_included=false` and `real_send_performed=false` are part of the contract.
