# Hermes Exposure Hardening

Goal 313 defines the readiness gate before SkyBridge treats the current Hermes direct API as safe for live escalation delivery or any worker execution-class action.

The read-only audit is:

```powershell
. "$HOME\.skybridge\hermes.env.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-hermes-exposure-readiness.ps1 `
  -Json
```

The output schema is `skybridge.hermes_exposure_readiness.v1`. It reports only redacted endpoint metadata, capability booleans, runtime mode, tool execution mode, risk classification, action allowances and safety flags. It must keep `token_printed=false`, `credential_values_exposed=false` and `raw_response_included=false`.

## Risk Model

`runtime_mode=server_agent` with `tool_execution=server` is high risk because a reachable Hermes API can do more than return planner text. Even with bearer auth and HTTPS, an exposed server-side tool execution runtime expands the blast radius of a compromised key, proxy rule, client machine or future send endpoint.

Worker heartbeat is lower risk than task execution. A heartbeat proves that one authorized worker is visible to SkyBridge; it must not claim work, run Codex, apply queues, send live escalation messages or advance campaign metadata. `start-one` and `run-until-hold` are execution-class actions and must remain blocked until the execution gates are satisfied.

## Required Gates

Before live admin escalation send or worker execution:

- Bearer auth is required.
- HTTPS is required.
- API host and Dashboard host are separated.
- Dashboard routes do not expose raw Hermes API routes.
- Public docs and workflows contain no secrets or real private endpoints.
- Token rotation runbook exists.
- Admin escalation send endpoint is narrow schema-only, not arbitrary prompt execution.
- Admin escalation endpoint does not accept arbitrary tool calls.
- Admin escalation endpoint sanitizes title, message and severity.
- Admin escalation endpoint returns `token_printed=false`.

For `server_agent` with `tool_execution=server`, add at least one second gate before any execution-class action:

- IP allowlist;
- shared internal header;
- endpoint-specific allowlist;
- separate low-privilege token.

The readiness script recognizes local boolean markers for these controls:

```powershell
$env:HERMES_SECOND_GATE_IP_ALLOWLIST_CONFIGURED = "true"
$env:HERMES_SECOND_GATE_SHARED_INTERNAL_HEADER_CONFIGURED = "true"
$env:HERMES_SECOND_GATE_ENDPOINT_ALLOWLIST_CONFIGURED = "true"
$env:HERMES_SECOND_GATE_LOW_PRIVILEGE_TOKEN_CONFIGURED = "true"
```

These markers are evidence pointers only. They must not contain secret values.

## Recommended Gates

- Rate limit.
- Audit log.
- Request id.
- Replay prevention for send endpoint.
- Separate token for admin escalation versus general Hermes responses.
- Emergency disable switch.

## Local Environment Split

Keep SkyBridge and Hermes configuration separate:

```powershell
# $HOME\.skybridge\skybridge.env.ps1
$env:SKYBRIDGE_API_BASE = "<PRIVATE_SKYBRIDGE_API_BASE>"

# $HOME\.skybridge\hermes.env.ps1
$env:HERMES_API_BASE = "<PRIVATE_HERMES_API_BASE>"
$env:HERMES_API_KEY = "<local Hermes key>"
```

Do not put `HERMES_API_KEY` in the SkyBridge env file. Do not set `SKYBRIDGE_API_BASE` to the Hermes API base.

## Current Expected Bootstrap State

The current bootstrap-compatible state can be:

```text
status = warning
risk_level = high
warnings includes hermes_server_tool_execution_enabled
allow_worker_heartbeat = true only when -AllowServerToolExecution is explicit
allow_start_one = false
allow_run_until_hold = false
token_printed = false
```

This state is acceptable for read-only audit and an explicitly authorized heartbeat-only proof. It is not acceptable for live admin escalation send, `start-one` or `run-until-hold`.
