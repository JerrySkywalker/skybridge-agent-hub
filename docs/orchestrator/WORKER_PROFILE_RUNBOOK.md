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

## Capability Semantics

Keep `task_type` separate from worker execution capabilities.

Task types describe the work class: `docs`, `local-smoke`, `test`, `frontend`, `backend`, `refactor`, and legacy `smoke`. Worker capabilities describe tools the machine can actually provide: `codex`, `git`, `gh`, `powershell`, `node`, `pnpm`, `windows` and `laptop`.

`docs` is not a hard worker capability. A docs task with expected files under `docs/` is normalized for execution to require `codex`, `git` and `gh`; legacy `required_capabilities=["docs"]` is preserved as original metadata but ignored for worker matching. A safe local-smoke task with expected files under `scripts/powershell/smoke-*.ps1` is normalized to require `codex`, `powershell` and `windows`, preserving raw `powershell`, `windows` or `laptop` entries when present.

Unsafe task types remain blocked regardless of normalization: production, deploy, secret, GitHub settings, branch protection, server config and server root config. Local-smoke tasks must pass the safe-local-smoke gate before a worker can match them.

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

The edge worker accepts new-format worker profiles directly. Users should keep clean profiles with `project_ids`, `repo_paths` and `skybridge_api_base`; generated `edge-worker.*.generated.json` runtime configs are no longer needed for normal use.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile "$HOME\.skybridge\worker.$env:COMPUTERNAME.json" `
  -ProjectId skybridge-agent-hub `
  -Loop `
  -MaxTasks 2 `
  -PollIntervalSeconds 30 `
  -IdleTimeoutSeconds 600 `
  -StopOnFailure `
  -Json
```

`-WorkerProfileFile` and `SKYBRIDGE_WORKER_PROFILE` remain supported aliases for explicitly selecting a profile. Legacy runtime configs that already contain `project_id`, `repo_path` and `api_base` are still supported for compatibility.

Bounded loop exits now restore project control to `paused`, clear `stop_requested`, and record `stop_reason`. This applies to normal caps, idle timeout and failure-stop exits, so operators can inspect the final state without leaving the cloud project in a stopped state.

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

Prefer a local token file outside the repository:

```powershell
New-Item -ItemType Directory -Path "$HOME\.skybridge\secrets" -Force | Out-Null
Set-Content -LiteralPath "$HOME\.skybridge\secrets\worker-token.txt" -Value "<local-only worker token>"
```

Point the profile at that file:

```json
{
  "auth_mode": "bearer_token",
  "token_file": "C:\\Users\\operator\\.skybridge\\secrets\\worker-token.txt"
}
```

A shell token is still supported for short-lived test sessions:

```powershell
$env:SKYBRIDGE_WORKER_TOKEN = "<local-only worker token>"
```

Run a dry-run remote profile smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-remote-profile.ps1 -DryRun
```

For the first real remote registration/heartbeat, use `docs/orchestrator/FIRST_REMOTE_WORKER_REGISTRATION.md` and:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-remote-skybridge-api.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -TokenEnvVar SKYBRIDGE_WORKER_TOKEN `
  -WorkerSmoke `
  -AuthFailureCheck `
  -Json
```

For day-to-day operator checks, use the profile-aware wrapper:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-status.ps1 `
  -Command register-heartbeat `
  -ConfigFile "$HOME\.skybridge\worker.$env:COMPUTERNAME.json" `
  -ProjectId skybridge-agent-hub
```

Use compact status and project control helpers instead of ad hoc `Invoke-RestMethod` snippets:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 `
  -Command pause `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"
```

For larger task history, prefer explicit status filters:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -ActiveOnly

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -RecentTasks 10

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -TaskStatus failed `
  -ExcludeRecovered

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -RecoveredOnly `
  -TaskLimit 20
```

For guided operator use, prefer `skybridge-guide.ps1`. It wraps the same safe primitives and prints the next suggested command after each step:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
  -Mode status `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"
```

Guide modes `status-active`, `status-recent`, `status-worker`, `status-task`, `status-failed` and `status-recovered` map to the same filtered status queries. The Hermes CLI facade exposes them as `operator status-active`, `operator status-recent`, `operator status-worker`, `operator status-task`, `operator status-failed` and `operator status-recovered`.

## Standard Operator Workflow

Use this sequence for one-shot remote work. The guided command names map directly to the underlying scripts:

1. Read compact status.
2. Optionally run `plan-preview` for a high-level master goal.
3. Optionally run `plan-apply` and review proposals before converting one.
4. Preview one goal/task submission or proposal conversion.
5. Apply one goal/task submission or proposal conversion.
6. Preview one bounded worker pass.
7. Apply one bounded worker pass.
8. Inspect task evidence.
9. Read compact status again.
10. Pause project control.

Guide preview modes are already dry-run. `skybridge-guide.ps1 -Mode plan-preview` accepts `-DryRun` for operator muscle memory, but it is not required; apply modes still require explicit `-Apply`.

Status:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"
```

Submit is dry-run by default. Add `-Apply` only when the task body and IDs are correct:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-submit.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -GoalId remote-worker-smoke-goal `
  -TaskId remote-docs-task-001 `
  -TaskTitle "Remote docs task" `
  -TaskBody "Update one docs file with a short pilot note." `
  -EnsureProject `
  -EnsureGoal `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -DryRun
```

Run one worker pass. This starts project control with `max_tasks=1`, registers/heartbeats the worker, runs `skybridge-edge-worker.ps1 -PollOnce`, and pauses control in a `finally` block:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -WorkerProfile "$HOME\.skybridge\worker.$env:COMPUTERNAME.json" `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -TaskId remote-docs-task-001 `
  -GoalId remote-worker-smoke-goal `
  -NoSubmit `
  -DryRun
```

Use `-Loop` only with explicit bounds (`-MaxTasks`, `-IdleTimeoutSeconds`, `-StopOnFailure`) and only after confirming the queue contains safe tasks for the selected worker profile. Use `-PollOnce` for single-task recovery or when the queue contents are not fully understood.

Guided equivalent:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
  -Mode submit-preview `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -GoalId remote-worker-smoke-goal `
  -GoalTitle "Remote worker smoke goal" `
  -TaskId remote-docs-task-001 `
  -TaskTitle "Remote docs task" `
  -TaskBody "Update one docs file with a short pilot note." `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"
```

The Hermes/SkyBridge facade can call the same guided workflow through the `operator` area:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area operator `
  -Command submit-preview `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -GoalId remote-worker-smoke-goal `
  -GoalTitle "Remote worker smoke goal" `
  -TaskId remote-docs-task-001 `
  -TaskTitle "Remote docs task" `
  -TaskBody "Update one docs file with a short pilot note." `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"
```

## CI Rerun And Evidence Repair

When a child PR is blocked by a transient checkout or fetch issue, classify it before changing task evidence:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-rerun-ci.ps1 `
  -PrNumber 57
```

The rerun helper is dry-run by default. Add `-Apply` only for one bounded rerun batch. If checks later pass and the child PR merges, append recovered evidence instead of erasing the original failed task event. Recovered task evidence is visible in `skybridge-status.ps1` as `display_status=recovered` and `evidence=recovered`; the original failed event and raw task status remain in task history.

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
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-remote-skybridge-api.ps1 -DryRun -Json
```
