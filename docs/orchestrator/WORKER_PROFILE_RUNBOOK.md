# Worker Profile Runbook

Worker profiles describe what a local machine is allowed to do for the SkyBridge control plane. They are local-only configuration files. Do not commit real profiles or worker tokens.

## Profile Files

Example profiles live in `config/`:

- `config/worker-profile.example.json`: local development template.
- `config/worker-profile.homepc.example.json`: single-machine home workstation template.
- `config/worker-profile.cloud.example.json`: placeholder cloud-control-plane template.

Real profiles should live outside the repository:

```powershell
$profile = Join-Path $HOME ".skybridge\worker.$env:COMPUTERNAME.json"
```

The loader uses that path by default when `-ConfigFile` is not provided. A repo-local profile may be used for short local experiments, but `config/worker-profile*.json` is ignored unless the filename ends with `.example.json`.

## Required Fields

Profiles currently support:

- `worker_id`
- `display_name`
- `project_ids`
- `repo_paths`
- `capabilities`
- `executor_adapters`
- `preferred_task_types`
- `blocked_task_types`
- `max_parallel_tasks`
- `allow_auto_merge`
- `allow_production_deploy`
- `allow_remote_server`
- `reject_insecure_http_for_remote`
- `skybridge_api_base`
- `auth_mode`
- `token_env_var`
- `token_file`
- `codex_command`
- `codex_sandbox`

`allow_production_deploy` must stay `false` for current workers. `max_parallel_tasks` should stay `1` until repository locking and conflict handling are explicit.

## Validate A Profile

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\load-worker-profile.ps1 `
  -ConfigFile .\config\worker-profile.example.json `
  -Json
```

The loader validates required fields, reports safe metadata and never prints worker token values.

To preview the edge-worker-compatible projection:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\load-worker-profile.ps1 `
  -ConfigFile .\config\worker-profile.example.json `
  -ProjectId skybridge-agent-hub `
  -AsEdgeWorkerConfig `
  -Json
```

## Edge Worker Usage

The edge worker still supports legacy `config/edge-worker.json`, but a worker profile is preferred when provided:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -WorkerProfileFile "$HOME\.skybridge\worker.$env:COMPUTERNAME.json" `
  -ProjectId skybridge-agent-hub `
  -Loop `
  -MaxTasks 2 `
  -PollIntervalSeconds 30 `
  -IdleTimeoutSeconds 600 `
  -StopOnFailure `
  -Json
```

Set `SKYBRIDGE_WORKER_PROFILE` to point the worker at a profile without passing `-WorkerProfileFile`.

## API Base And Worker Token

Local development uses:

```text
SKYBRIDGE_API_BASE=http://127.0.0.1:8787
```

Cloud control plane workers should use HTTPS:

```text
SKYBRIDGE_API_BASE=https://skybridge.example.invalid
```

Remote worker registration uses bearer token auth:

```text
SKYBRIDGE_WORKER_TOKEN=<local-only token>
SKYBRIDGE_WORKER_TOKEN_FILE=C:\Users\operator\.skybridge\worker-token.txt
```

Profiles may use either:

```json
{
  "auth_mode": "bearer_token",
  "token_env_var": "SKYBRIDGE_WORKER_TOKEN",
  "token_file": "C:\\Users\\operator\\.skybridge\\worker-token.txt",
  "allow_remote_server": true,
  "reject_insecure_http_for_remote": true
}
```

The worker first checks `token_env_var`, then the profile `token_file`, then `SKYBRIDGE_WORKER_TOKEN_FILE`. Token values are not printed.

`reject_insecure_http_for_remote=true` requires HTTPS for non-localhost API bases. Localhost and `127.0.0.1` may use HTTP for development.

## Remote Profile Example

Start from the placeholder cloud profile:

```powershell
Copy-Item .\config\worker-profile.cloud.example.json "$HOME\.skybridge\worker.$env:COMPUTERNAME.json"
```

Edit only the local copy. Set `skybridge_api_base` to the HTTPS SkyBridge Server URL, keep `auth_mode` as `bearer_token`, set `allow_remote_server` to `true` and keep `allow_production_deploy` as `false`.

Set a token through the current shell:

```powershell
$env:SKYBRIDGE_WORKER_TOKEN = "<local-only worker token>"
```

Or store it in a local file outside the repository and point the profile at that file:

```powershell
Set-Content -LiteralPath "$HOME\.skybridge\worker-token.txt" -Value "<local-only worker token>"
```

Run a dry-run remote profile smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-remote-profile.ps1 -DryRun
```

Run a real remote smoke only when the explicit API base and token are present:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-remote-profile.ps1 `
  -ApiBase https://skybridge.example.com `
  -TokenEnvVar SKYBRIDGE_WORKER_TOKEN `
  -RunReal
```

## Troubleshooting

`401 missing_worker_token` means the server requires bearer auth but the request did not include an `Authorization: Bearer` header. Check `auth_mode`, `token_env_var`, `token_file` and local shell environment.

`403 invalid_worker_token` means a token was sent but does not match the server-side `SKYBRIDGE_WORKER_TOKEN` or `SKYBRIDGE_WORKER_TOKENS_FILE`.

`Remote SkyBridge api_base must use HTTPS` means the profile points at a non-localhost HTTP URL while `reject_insecure_http_for_remote` is enabled.

If the machine sleeps or loses network, restart the bounded loop after confirming `/v1/health`, GitHub auth, Codex availability and repo cleanliness. The worker should not claim new tasks while degraded.

When running behind a reverse proxy, ensure the proxy forwards `Authorization` headers and does not expose the Hermes API.

## Safety

- Real profiles and tokens stay outside the repository.
- Token values are not printed by loader or worker API helpers.
- Hermes API credentials are separate and must remain private.
- Codex executes locally as an `ExecutorAdapter`.
- Auto-merge remains governed by existing lifecycle and merge policy.
- Production deployment is disabled by profile default.

## Smoke Test

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-profile.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-token-auth.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-token-auth-failure.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-remote-profile.ps1 -DryRun
```
