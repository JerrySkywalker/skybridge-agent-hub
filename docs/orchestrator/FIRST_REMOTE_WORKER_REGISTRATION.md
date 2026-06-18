# First Remote Worker Registration

This runbook validates the first remote worker registration and heartbeat against a SkyBridge Server API endpoint such as:

```text
https://skybridge.example.com
```

No real token belongs in this repository. Prefer a local token file outside the repository so worker commands do not depend on inherited shell environment.

## Server Prerequisites

- DNS points `skybridge.example.com` to the server.
- HTTPS is active and trusted by the worker machine.
- SkyBridge Server is running behind the reverse proxy.
- `/v1/health` returns a healthy response.
- Server-side worker auth is configured with `SKYBRIDGE_WORKER_TOKEN` or `SKYBRIDGE_WORKER_TOKENS_FILE`.
- Hermes API is not proxied publicly.

## Local Worker Token

Preferred local token file:

```powershell
New-Item -ItemType Directory -Path "$HOME\.skybridge\secrets" -Force | Out-Null
Set-Content -LiteralPath "$HOME\.skybridge\secrets\worker-token.txt" -Value "<local-only worker token>"
```

An environment variable also works for short-lived shells:

```powershell
$env:SKYBRIDGE_WORKER_TOKEN = "<local-only worker token>"
```

## Local Worker Profile

Start from the checked-in example and copy it outside the repository:

```powershell
New-Item -ItemType Directory -Path "$HOME\.skybridge" -Force | Out-Null
Copy-Item .\docs\orchestrator\worker.homepc.remote.example.json `
  "$HOME\.skybridge\worker.$env:COMPUTERNAME.json"
```

Edit the local copy so that:

- `skybridge_api_base` is `https://skybridge.example.com`;
- `auth_mode` is `bearer_token`;
- `allow_remote_server` is `true`;
- `reject_insecure_http_for_remote` is `true`;
- `token_env_var` or `token_file` points at the local token source;
- `allow_production_deploy` stays `false`.

For token-file auth, keep the profile field pointed at the local-only path:

```json
{
  "auth_mode": "bearer_token",
  "token_file": "C:\\Users\\operator\\.skybridge\\secrets\\worker-token.txt"
}
```

## Smoke Command

Dry-run request construction:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-remote-skybridge-api.ps1 `
  -DryRun `
  -Json
```

Real remote registration and heartbeat, only after local token setup:

```powershell
$env:SKYBRIDGE_REMOTE_API_BASE = "https://skybridge.example.com"
$env:SKYBRIDGE_WORKER_TOKEN = "<local-only worker token>"

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-remote-skybridge-api.ps1 `
  -ApiBase $env:SKYBRIDGE_REMOTE_API_BASE `
  -TokenEnvVar SKYBRIDGE_WORKER_TOKEN `
  -WorkerSmoke `
  -AuthFailureCheck `
  -Json
```

If using `token_file`, validate the actual worker profile directly:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-status.ps1 `
  -Command register-heartbeat `
  -ConfigFile "$HOME\.skybridge\worker.$env:COMPUTERNAME.json" `
  -ProjectId skybridge-agent-hub
```

Inspect compact project state without printing the token:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.example.com `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"
```

After registration works, submit and execution should use the one-shot operator path instead of handwritten API calls:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-submit.ps1 `
  -ApiBase https://skybridge.example.com `
  -ProjectId skybridge-agent-hub `
  -GoalId remote-worker-smoke-goal `
  -TaskId remote-docs-task-001 `
  -TaskTitle "Remote docs task" `
  -TaskBody "Update one docs file with a short pilot note." `
  -EnsureProject `
  -EnsureGoal `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -DryRun

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
  -ApiBase https://skybridge.example.com `
  -ProjectId skybridge-agent-hub `
  -WorkerProfile "$HOME\.skybridge\worker.$env:COMPUTERNAME.json" `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -TaskId remote-docs-task-001 `
  -GoalId remote-worker-smoke-goal `
  -NoSubmit `
  -DryRun
```

`skybridge-run-once.ps1` uses `-PollOnce` only and attempts to restore project control to `paused` before exiting. Keep the long-running loop disabled for remote work until the next explicit pilot.

Expected success shape:

```json
{
  "DryRun": false,
  "HealthOk": true,
  "WorkerSmoke": {
    "Registered": true,
    "HeartbeatStatus": "online"
  },
  "AuthFailureCheck": {
    "MissingTokenRejected": true,
    "WrongTokenRejected": true
  },
  "TokenPrinted": false
}
```

## Troubleshooting

`401 missing_worker_token`: the server requires worker auth but the request did not include a bearer token. Check `TokenEnvVar`, `TokenFile` and the local shell environment.

`403 invalid_worker_token`: the token was sent but does not match the server-side token configuration. Rotate or resync the server and worker token values.

`502 Bad Gateway`: the reverse proxy cannot reach SkyBridge Server. Check the container/process, loopback bind, port and upstream address.

TLS errors: confirm the certificate is valid for `skybridge.example.com`, the full chain is installed and the worker machine trusts it.

Proxy/SSE issues: preserve `Authorization`, `Host`, `X-Forwarded-Proto`, disable buffering for `/v1/stream`, and keep long read timeouts.

Hermes exposure: if any public route reaches Hermes, disable it before running remote worker smokes.
