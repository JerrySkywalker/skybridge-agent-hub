# Hermes Direct API

Hermes preview can use a private direct HTTPS API endpoint for daily operation.
Public docs must show placeholders only:

```text
Windows / Codex / SkyBridge scripts
  -> <PRIVATE_HERMES_API_BASE> or https://api.hermes.example.com
  -> OpenResty
  -> 127.0.0.1:8642 Hermes API server
```

The real private endpoint belongs in a local, untracked environment file such as
`$HOME\.skybridge\hermes.env.ps1`, or in process environment variables. Do not
publish the real Hermes API hostname, raw env file, bearer token, auth header,
webhook, tunnel host, provider hostname or production topology in issues, PRs,
docs or examples.

SkyBridge has a separate local env file:

```powershell
$HOME\.skybridge\skybridge.env.ps1
```

That file should contain `SKYBRIDGE_API_BASE` and point to the SkyBridge Server
API. It should not contain `HERMES_API_KEY`.

Hermes uses:

```powershell
$HOME\.skybridge\hermes.env.ps1
```

That file contains `HERMES_API_BASE` and `HERMES_API_KEY` and points to the
Hermes API. `SKYBRIDGE_API_BASE` is not `HERMES_API_BASE`; setting them equal
will make SkyBridge operator verification fail early.

The old local SSH tunnel path, `http://127.0.0.1:18642`, is still useful as a rollback path, but it is deprecated for routine preview work because it depends on an operator-local tunnel process.

Current tunnel mode can be inspected without printing secrets:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-health.ps1 `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1"
```

Run the exposure hardening audit before any live escalation send, worker
heartbeat proof or execution-class action:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-hermes-exposure-readiness.ps1 `
  -Json
```

The audit reads `HERMES_API_BASE` and `HERMES_API_KEY` from the local Hermes env
loader, calls only `/v1/capabilities`, redacts the endpoint, excludes raw
Hermes responses and reports `token_printed=false`.

## Requirements

- Endpoint: `HERMES_API_BASE` must come from `$HOME\.skybridge\hermes.env.ps1`
  or an equivalent local environment source.
- DNS/TLS: configure them privately for the real endpoint. Public docs use
  `https://api.hermes.example.com` or `<PRIVATE_HERMES_API_BASE>` only.
- Backend: proxy only the Hermes API server at `127.0.0.1:8642`.
- Dashboard: do not expose the Hermes Dashboard through the Hermes API host.
- Auth: preserve `Authorization: Bearer <HERMES_API_KEY>` and keep bearer auth mandatory.
- Second gate: when `runtime_mode=server_agent` and `tool_execution=server`, an
  IP allowlist, shared internal header, endpoint-specific allowlist or separate
  low-privilege token is required before execution-class actions.
- Streaming: keep long proxy timeouts and disable buffering for planning calls and SSE-style responses. The example uses `proxy_read_timeout 600s`, `proxy_send_timeout 600s`, `proxy_connect_timeout 60s`, `send_timeout 600s`, `proxy_buffering off` and `proxy_request_buffering off`.

Authelia is not required for API clients because Hermes bearer authentication is
the API-level gate. Do not use the API hostname as a Dashboard hostname.

## OpenResty Example

Use [openresty-hermes-api.example.conf](openresty-hermes-api.example.conf) as the manual starting point. The autonomous repo workflow must not install or modify server root config.

## Local Environment

Update the local Hermes env file after the HTTPS route is configured:

```powershell
$env:HERMES_API_BASE = "<PRIVATE_HERMES_API_BASE>"
$env:HERMES_API_KEY = "<existing local key value>"
$env:HERMES_MODEL = "<optional model>"
```

Keep this in `$HOME\.skybridge\hermes.env.ps1`. Do not commit the file, paste it
into a PR/issue/doc, or print the key.

Keep the SkyBridge server base in `$HOME\.skybridge\skybridge.env.ps1`:

```powershell
$env:SKYBRIDGE_API_BASE = "<PRIVATE_SKYBRIDGE_API_BASE>"
```

SkyBridge operator scripts resolve explicit `-ApiBase` first, then
`$env:SKYBRIDGE_API_BASE`, then the public placeholder
`https://skybridge.example.com`. Live runs reject placeholders and Hermes-like
metadata before route probing.

## Verification

Health/capabilities:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-health.ps1 `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1"
```

Raw capabilities test when debugging:

```powershell
. "$HOME\.skybridge\hermes.env.ps1"
$headers = @{ Authorization = "Bearer $env:HERMES_API_KEY" }
Invoke-RestMethod -Method Get -Uri "$env:HERMES_API_BASE/v1/capabilities" -Headers $headers
```

Responses API test:

```powershell
. "$HOME\.skybridge\hermes.env.ps1"
$headers = @{ Authorization = "Bearer $env:HERMES_API_KEY" }
$body = @{
  model = if ($env:HERMES_MODEL) { $env:HERMES_MODEL } else { "default" }
  input = "Return strict JSON: {`"ok`":true}"
  response_format = @{ type = "json_object" }
} | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method Post -Uri "$env:HERMES_API_BASE/v1/responses" `
  -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 600
```

Preview wrapper:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-preview.ps1 `
  -ApiBase <PRIVATE_SKYBRIDGE_API_BASE> `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-hermes-assisted-self-bootstrap-preview `
  -Title "Hermes-assisted SkyBridge self-bootstrap preview" `
  -Description "Use Hermes as an advisory planner to propose safe docs-only or local-smoke tasks for a bounded SkyBridge self-bootstrap sprint." `
  -ConstraintsFile .agent/tmp/hermes-preview-constraints.json `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -StateMode compact `
  -MaxHermesAttempts 3 `
  -RetryDelaySeconds 10 `
  -TimeoutSeconds 600 `
  -OutputFile .agent/tmp/hermes-preview-176.json
```

Confirm no SSH tunnel is required, `/v1/capabilities` succeeds, `hermes-preview` succeeds, proposals are visible in both `proposals` and `planning_session.proposals`, no cloud task is created, and project control remains paused.

The safe exposure audit must classify `server_agent/tool_execution=server` as
high risk. That state can be compatible with a documented heartbeat-only proof
when explicitly allowed, but it does not allow live admin escalation send,
`start-one` or `run-until-hold` until the second gate is satisfied.

The preview wrapper saves full JSON when `-OutputFile` is supplied. Add:

```powershell
-SummaryOutputFile .agent/tmp/hermes-preview-summary.json
```

to save a compact quality report with endpoint, provider, model, runtime mode, planner mode, tool execution mode, prompt version, input state hash, decision counts and per-proposal risk/type/files/rationale. `.agent` files stay local and untracked.

## Capabilities OK, Responses 504

If `/v1/capabilities` succeeds but `/v1/responses` returns `502`, `503` or `504`, treat it as a proxy or long-response path problem before changing planner policy.

1. Run `skybridge-hermes-health.ps1` to confirm bearer auth, DNS and the capabilities route.
2. Run the small responses test above with `-TimeoutSec 600`.
3. Confirm the OpenResty route uses the timeout and streaming settings from the example: `proxy_read_timeout 600s`, `proxy_send_timeout 600s`, `proxy_connect_timeout 60s`, `send_timeout 600s`, `proxy_buffering off`, `proxy_request_buffering off`, `gzip off` and `X-Accel-Buffering no`.
4. Prefer `skybridge-hermes-preview.ps1 -StateMode compact -MaxHermesAttempts 3 -TimeoutSeconds 600` for real preview. Compact state avoids sending full task event histories through `/v1/responses`.
5. If the tiny responses test passes but real preview still times out, inspect OpenResty and Hermes API logs for upstream timeout, request body size, worker timeout or streaming flush errors. Do not expose the Dashboard or bypass bearer auth during diagnosis.

## Rollback

If direct HTTPS is not ready, restore the tunnel base in `$HOME\.skybridge\hermes.env.ps1`:

```powershell
$env:HERMES_API_BASE = "http://127.0.0.1:18642"
```

Then start or recover the private tunnel before running health or preview. Treat this as a fallback only; daily operation should use direct HTTPS once configured.
