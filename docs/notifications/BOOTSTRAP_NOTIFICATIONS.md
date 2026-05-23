# Bootstrap Notifications

SkyBridge's own development automation cannot assume the SkyBridge Notification Center is online. Controller, CI Guardian and Hermes supervisor scripts must have a direct phone-notification path for critical lifecycle messages.

`scripts/powershell/notify-bootstrap.ps1` is that path. It sends directly to ntfy using environment variables, and it can also send urgent messages to a WeCom/WeChat webhook. It does not call the SkyBridge server.

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

## Troubleshooting

Missing local env:
If dry-run output reports `missing_ntfy_env`, the notifier did not find a usable topic URL. Set either the preferred `SKYBRIDGE_BOOTSTRAP_NTFY_URL` plus `SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC` pair, or the legacy `NTFY_TOPIC_URL`. On a local workstation, keep these values in `$HOME\.skybridge\bootstrap-notify.env.ps1` or another local secret store, not in repository files.

Configured but not sent:
If output reports `send_flag_required`, the notifier found configuration but intentionally did not deliver because `-Send` was omitted. This is the expected default for smoke tests, controller dry-runs and CI. Add `-Send` only for a deliberate operator phone test.

Wrong topic or phone does not alert:
Confirm the phone is subscribed to the exact ntfy topic selected by severity. `urgent` may use `SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC`; other severities use `SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC`. Do not paste real topic names into issues, PRs or docs when debugging.

ACL or auth denied:
HTTP 401 or 403 errors usually mean the ntfy server requires a token or basic auth, the token lacks publish permission for the topic, or the topic ACL denies the configured user. Rotate or update credentials outside the repository and rerun a dry-run before trying `-Send`.

Sandbox mode:
When the notification path is invoked through nested `codex exec` on Windows, use the documented smoke wrapper or run Codex with `--sandbox danger-full-access` so it can spawn local PowerShell reliably. The nested prompt must still call only `notify-bootstrap.ps1`, avoid printing environment values and avoid file edits.
