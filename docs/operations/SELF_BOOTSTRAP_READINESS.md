# Self-Bootstrap Readiness Audit

`skybridge-self-bootstrap-readiness.ps1` is a read-only operator audit for the intended queue-driven, Hermes-audited SkyBridge self-bootstrap loop.

The audit answers one question: can a later, explicitly authorized operator command safely start one bounded task or continue until the next hold? It does not start Codex, claim tasks, call queue apply, advance campaign metadata, trigger Deploy Cloud, create tags or mutate the cloud host.

## Run

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-self-bootstrap-readiness.ps1 -Json
```

For a cloud readiness audit, load the SkyBridge API base from the local
SkyBridge operator env file first:

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-self-bootstrap-readiness.ps1 -Json
```

`$HOME\.skybridge\skybridge.env.ps1` contains `SKYBRIDGE_API_BASE` and points
to the SkyBridge Server API. `$HOME\.skybridge\hermes.env.ps1` contains
`HERMES_API_BASE` and `HERMES_API_KEY` and points to Hermes. Keep them separate:
`SKYBRIDGE_API_BASE` is not `HERMES_API_BASE`.

Useful options:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-self-bootstrap-readiness.ps1 `
  -ApiBase https://skybridge.example.com `
  -ProjectId skybridge-agent-hub `
  -CampaignId dev-queue-189-200 `
  -Json
```

For authenticated read-only status endpoints, pass `-TokenFile` or `-TokenEnvVar`. For Hermes, pass `-HermesEnvFile` or `-HermesApiBase` when the default local Hermes environment loader is not enough.
SkyBridge ApiBase resolution uses explicit `-ApiBase`, then
`$env:SKYBRIDGE_API_BASE`, then the public placeholder. Live runs fail early
when the resolved value is a placeholder, empty, invalid, or points to Hermes.

## Output Contract

The script emits:

```text
schema = skybridge.self_bootstrap_readiness.v1
status = ready | blocked | partial | unknown
can_start_one = true | false
can_run_until_hold = true | false
allow_worker_heartbeat = true | false
allow_start_one = true | false
allow_run_until_hold = true | false
blockers = [...]
warnings = [...]
required_human_action = string
token_printed = false
```

It also includes safe summaries for:

- git branch, clean status, HEAD and main commit;
- cloud `/v1/version` commit and image reference;
- cloud route parity;
- latest Deploy Cloud evidence from `skybridge-verify-cloud-autodeploy.ps1`;
- project control state;
- queued, claimed, running, stale lease and stale task counts;
- worker online/stale/offline counts;
- campaign queue counts;
- Hermes health with a redacted endpoint only;
- Hermes exposure readiness and execution risk classification;
- administrator escalation readiness;
- notification provider status.

The report intentionally excludes raw prompts, raw Hermes responses, raw logs, token values, cookies, credentials and environment dumps.

## Readiness Policy

`ready` requires all of these to be true:

- current branch is `main`;
- worktree is clean;
- cloud `/v1/version` matches the local main commit;
- cloud route parity is `ok`;
- Deploy Cloud evidence is successful for the same main commit;
- project control is not running and stop is not requested;
- no queued, claimed, running or stale task residue exists;
- at least one worker is online;
- at least one campaign is ready or paused;
- Hermes health is OK over direct HTTPS;
- Hermes exposure readiness allows execution-class actions;
- administrator escalation through the current Hermes WeChat or WeCom path is ready;
- `token_printed=false`.

Hermes exposure is reported separately from admin escalation. Admin escalation
readiness means the current dry-run path can evaluate blocker notice delivery
semantics. It does not prove live delivery. A real send remains unproven unless
`skybridge-admin-escalation-test.ps1 -Send` is explicitly authorized and returns
safe delivery evidence.

If Hermes reports `runtime_mode=server_agent` and `tool_execution=server`,
self-bootstrap readiness adds `hermes_server_tool_execution_enabled` and treats
Hermes exposure as high risk. Worker heartbeat may remain allowed only as a
heartbeat-only proof when no blocker other than `worker_offline` prevents it.
`start-one` and `run-until-hold` remain blocked until the second gate is
satisfied and the exposure audit allows execution.

Goal 308 proved the readiness semantics for the current bootstrap administrator escalation path. It verifies that the configured channel is Hermes WeChat or WeCom, that Hermes is reachable over direct HTTPS, and that the path can send blocker notices. It does not send a real message.

Goal 309 adds an explicit operator-triggered send-test for the same path. The current bootstrap administrator escalation path is:

```text
SkyBridge hold / ask_human / blocker
-> safe escalation summary
-> cloud Hermes
-> WeChat / WeCom notification to the administrator
```

SkyBridge Notification Center providers and Jerry's future custom notify gateway remain the long-term primary notification path. They are not the current hard blocker for self-bootstrap start-one readiness when Hermes administrator escalation is available. If native providers such as ntfy, Apprise, Gotify, Bark, WeCom, FCM or Xiaomi Push are all skipped while admin escalation is ready, readiness reports `skybridge_notification_center_not_ready` as a warning instead of `notification_provider_unavailable` as a blocker.

If admin escalation is unavailable, readiness blocks with `admin_escalation_unavailable`. `can_start_one` and `can_run_until_hold` both require admin escalation readiness. `can_run_until_hold` additionally requires no blockers plus Hermes OK over direct HTTPS.

The send-test command is dry-run by default:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-admin-escalation-test.ps1 `
  -Title "SkyBridge self-bootstrap hold test" `
  -Message "Operator-triggered bootstrap-test admin escalation dry run." `
  -Severity warning `
  -Json
```

Real delivery requires `-Send` and a configured Hermes admin escalation send endpoint. Without that contract, the script reports `delivery_status=send_endpoint_not_available`, `ok=false` and `send_performed=false`; it must not claim live delivery. When the endpoint exists, the one explicit live command is the same command with `-Send`, `-HermesApiBase` or `-HermesEnvFile` as needed, and a configured `HERMES_ADMIN_ESCALATION_SEND_PATH`.

The send-test message is bounded to `project_id`, `environment=bootstrap-test`, `severity`, short reason and timestamp. It excludes raw logs, prompts, patches, stdout/stderr, tokens, cookies, auth headers, webhooks, private keys, raw Hermes responses and raw notification payloads.

`blocked` means at least one hard gate failed. The script reports a concise `required_human_action`; use the relevant operator flow to repair the condition. This script must not be used to repair or apply anything.

`partial` means no hard blocker was found, but one or more optional signals were unavailable or warning-only evidence needs review.

## Smokes

Run the fixture-only smoke suite:

```powershell
corepack pnpm smoke:self-bootstrap-readiness
```

The smoke covers:

- ready report;
- blocked report when the worker is offline;
- blocked report when stale leases are present;
- blocked report when Hermes is unavailable;
- high-risk Hermes exposure when server-side Hermes tool execution is enabled;
- warning-only skipped SkyBridge Notification Center providers when admin escalation is ready;
- blocked report when admin escalation is unavailable;
- blocked report when admin escalation credential exposure is detected;
- `token_printed=false` and no secret-like output.

These smokes write only ignored fixture files under `.agent/tmp/self-bootstrap-readiness-smoke/`.

Run the focused admin escalation probe smoke:

```powershell
corepack pnpm smoke:admin-escalation-readiness
```

The admin escalation probe is dry-run/read-only by default. It does not send a real WeChat or WeCom message unless a future explicit send/apply flag is introduced and authorized. Readiness and probe output must not include secrets, raw Hermes responses, raw prompts, raw logs, raw notification payloads, webhooks, tokens, cookies, private keys, auth headers or production config values.

Run the focused Goal 309 send-test smoke:

```powershell
corepack pnpm smoke:admin-escalation-test
```

The send-test smoke is fixture-only. It covers dry-run no-send, fixture send success, missing endpoint no-fake-success, unsafe message blocking and safe output flags.
