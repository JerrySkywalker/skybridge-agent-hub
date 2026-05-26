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
- `skybridge_api_base`
- `auth_mode`
- `token_env_var`
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

Remote worker registration is expected to require a worker token:

```text
SKYBRIDGE_WORKER_TOKEN=<local-only token>
SKYBRIDGE_WORKER_TOKEN_FILE=C:\Users\operator\.skybridge\worker-token.txt
```

The current implementation creates the boundary and forwards a bearer header when a token is configured. Token issuing, rotation, revocation and production auth policy remain future work.

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
```
