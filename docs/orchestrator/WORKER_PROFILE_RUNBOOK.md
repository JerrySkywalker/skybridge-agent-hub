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

## Lease And Workspace Guards

Task execution is guarded in two layers:

- Server task leases: claim creates an active lease, start refreshes it, complete/fail/block releases it, and heartbeat can refresh the current active lease.
- Local workspace guards: the worker requires an active lease on the claimed task, refuses dirty worktrees, refuses duplicate child PR execution, checks branch collisions and acquires a repo lock before Codex starts.

The local repo lock is written under `.agent/locks/skybridge-edge-worker.lock.json` and includes `task_id`, `worker_id`, `pid` and `created_at`. Stale locks are archived, not blindly overwritten. The worker removes its own lock in `finally`.

If a cloud control plane has not deployed lease support, claimed tasks will not include an active lease. Current workers must block instead of starting Codex in that state.

Status operators can inspect lease-aware task views with:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ShowLeases
```

## Dev Queue Watch And Control

For the Goal 189-200 dev queue, use the laptop worker profile and keep the project paused until the reviewed launch command is run from clean latest `main`.

Recommended operator workflow:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command preflight -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command watch -PollIntervalSeconds 5 -RenderIntervalMilliseconds 250 -ColorMode Always
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command start-one -Apply -Json
```

Keep the watch command in a separate window. If Goal 189 succeeds, run `start-all -Apply -Json`; if the runner holds, run `report -Json` and inspect the current step, PR, CI and evidence fields before resuming. Use `safe-pause -Apply -Reason` for normal holds and `emergency-stop -Apply -Reason` only when the runner must be interrupted immediately. `unlock-stale-runner -Apply -Reason` is only for inspected stale runner locks; active locks are not force-unlocked by the wrapper.

Goal 188D fixed a JSON parsing edge case in the control wrapper: child scripts can emit diagnostic prefix lines before their JSON payload, especially around git operations. The wrapper now extracts the final JSON payload and reports whether mixed output was seen. The watch command also separates render cadence from polling cadence, so operators can keep a smooth spinner without increasing API polling frequency. Keep `-PollIntervalSeconds 5` and `-RenderIntervalMilliseconds 250` for launch-day monitoring.

Campaign status is metadata-only and does not start workers. Operators can inspect imported Goal Packs and deterministic advance gates with:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ShowCampaigns `
  -CampaignLimit 10

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 advance-preview `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -CampaignId bootstrap-mvp
```

Do not run a worker loop merely because a campaign step is ready. Campaign advance and worker execution stay separate operator actions.

Super 186 adds Hermes advisory gate commands for campaign metadata advance:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 hermes-gate-preview `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -CampaignId bootstrap-mvp `
  -UseHermesGate `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1"

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 advance-with-gate `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -CampaignId bootstrap-mvp `
  -UseHermesGate `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1" `
  -HumanApproved `
  -HumanApprovalReason "Operator approved metadata-only advance."
```

These commands still do not execute a worker. A ready campaign step must be converted into approved proposals and tasks through the normal review queue before `laptop-zenbookduo` may run anything.

Super 187 adds restartable campaign MVP expectations for workers and operators:

- a campaign lock is distinct from the worker repo lock under `.agent/locks` and from server task leases;
- a stale campaign lock should block campaign mutation until an operator previews recovery and applies it with a reason;
- workers should not treat a ready campaign step as executable work unless a normal approved task has been created;
- one active campaign per project is the default safety posture;
- campaign retry, skip and hold evidence should be attached to the campaign step before any new task is converted.

Before executing work derived from a campaign step, confirm the status view shows no unrelated active task residue and no stale leases:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ActiveOnly

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -Hygiene
```

If the step is being resumed after an interrupted session, inspect the campaign event log, child PR evidence and validation status first. Do not re-run Codex simply because the previous terminal was interrupted.

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

## Status Query Examples

Use `skybridge-status.ps1` for safe compact views. It prints task and worker summaries, never token values. For larger task history, prefer explicit filters:

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
  -WorkerId laptop-zenbookduo `
  -TaskLimit 20

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -TaskId remote-docs-task-001 `
  -EventLimit 10

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

`skybridge-status.ps1` prints a grouped header and grouped task summary. The display summary distinguishes all project tasks (`total`), filter matches (`matching`), rows actually displayed (`shown`) and truncation (`truncated`). `-ActiveOnly` with no queued, claimed or running tasks reports `matching=0`, `shown=0` and `Tasks: none`.

Proposal queue status is opt-in:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -ShowProposals `
  -ProposalLimit 10
```

Use `-ApprovedOnly` before conversion and `-PendingReviewOnly` before review sessions.

## Standard Operator Workflow

Use this sequence for one-shot remote work. The guided command names map directly to the underlying scripts:

1. Read compact status.
2. Optionally run `plan-preview` for a high-level master goal.
3. Optionally run `plan-apply` and review proposals before approving and converting one.
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

Proposal review flow:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
  -Mode proposal-list `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
  -Mode proposal-approve `
  -ProposalId proposal-id `
  -Reason "reviewed low-risk docs scope" `
  -Apply

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
  -Mode proposal-convert `
  -ProposalId proposal-id `
  -Apply
```

Every review mutation requires `-Apply`; reject and defer require `-Reason`.

## CI Rerun And Evidence Repair

When a child PR is blocked by a transient checkout or fetch issue, classify it before changing task evidence:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-rerun-ci.ps1 `
  -PrNumber 57
```

The rerun helper is dry-run by default. Add `-Apply` only for one bounded rerun batch. If checks later pass and the child PR merges, append recovered evidence instead of erasing the original failed task event. Recovered task evidence is visible in `skybridge-status.ps1` as `display_status=recovered` and `evidence=recovered`; the original failed event and raw task status remain in task history.

## Lease-backed Approved Batch Loop

Super 183 proved the approved-proposal batch loop with `laptop-zenbookduo` and `MaxTasks <= 2`.

Operator sequence:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ActiveOnly

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  approve `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Reason "approved low-risk docs scope" `
  -Apply

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  convert `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Apply

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile "$HOME\.skybridge\worker.laptop-zenbookduo.json" `
  -Loop `
  -MaxTasks 2 `
  -IdleTimeoutSeconds 120 `
  -PollIntervalSeconds 5 `
  -StopOnFailure
```

Required preconditions:

- project control is paused with `stop_requested=false`;
- no unrelated queued, claimed or running tasks exist;
- proposals are approved before conversion;
- converted tasks carry approval metadata, normalized capabilities and explicit expected files;
- worker heartbeat is online;
- local worktree is clean.

Execution guard expectations:

- claiming a task creates an active lease;
- the worker refuses Codex execution without an active lease for the current worker;
- dirty tree, active PR, active branch and branch collision guards pass before Codex starts;
- the repo lock is acquired before execution and released in `finally`;
- per-task logs stay under `.agent/workers/<worker>/<task>/`;
- evidence repair is allowed only after the child PR checks pass and the PR merges.

Useful status checks:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ActiveOnly
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ShowLeases
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ShowLocks
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ShowProposals -ApprovedOnly
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -Hygiene
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hygiene.ps1 audit -Json
```

## Campaign Step Execution

Campaign steps stay metadata-only until an operator explicitly previews and applies execution:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 execute-preview `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -CampaignId bootstrap-mvp `
  -WorkerId laptop-zenbookduo

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 execute-step `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -CampaignId bootstrap-mvp `
  -WorkerId laptop-zenbookduo `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -Apply
```

`execute-step` creates one queued, campaign-step-derived task and links it to the campaign step. It does not start the worker. Run the normal bounded worker loop afterward with an explicit target or `MaxTasks <= 2`.

Super 187 proved the first campaign-step execution: task `campaign-step-super-187-bootstrap-campaign-mvp-hardening-20260531100053` used lease `lease_chdDfMPI1SEIgonHR-hzv`, created child PR #92, merged after checks passed, recorded recovered evidence, and advanced `bootstrap-mvp` to Super 184B ready through the gate. Super 184B was not executed.

`skybridge-status.ps1` color is optional. Use `-Color` for interactive operator sessions, `-NoColor` for copyable logs and smokes, or `-ColorMode Auto|Always|Never` for explicit control. JSON output and `-OutputFile` never contain ANSI color.

Queue hygiene semantics:

- stale lease: active lease past expiry, active lease on an inactive task, or active lease whose worker is stale/offline;
- stale task: claimed/running too long, claimed/running without a lease, expired lease, or failed task with PR evidence needing repair;
- proposal reconciliation: raw proposal status is preserved, but converted proposals derive `executed` when the converted task completed or recovered.

Recovery commands are intentionally explicit:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hygiene.ps1 recover-lease `
  -TaskId task-id `
  -LeaseId lease-id `
  -Reason "operator reviewed stale lease" `
  -DryRun
```

Use `-Apply` only after reviewing the task, lease and expected files. Do not automatically requeue old failed tasks, do not unblock `task_proposal-59a0236fb69800cd`, and do not recover production/high-risk work through the hygiene command.

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

## Goal 188 Runner Profile

The Goal 188 autonomous runner is expected to use the `laptop-zenbookduo` worker profile for the initial development queue. The launch wrapper defaults to that profile and keeps execution bounded with `MaxSteps`, `MaxTasks`, `MaxRuntimeMinutes`, `StopOnFailure`, `AllowAutoMerge` and `AllowEvidenceRepair`.

Before starting a real queue run, verify the worker can heartbeat, project control is paused, `stop_requested=false`, active queued/claimed/running tasks are zero and stale leases are zero. The runner must be stopped or held before the operator exits.

Do not run the `dev-queue-189-200` unattended queue from an unmerged feature branch. Goal 188A expanded the Goal 189-200 files and fixed launch dry-run UX; those changes must be merged and reviewed before launch.

Dry-run validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-dev-queue-189-200.ps1 `
  -GoalPackDir .\goals\dev-queue-189-200 `
  -CampaignId dev-queue-189-200 `
  -MaxSteps 12 `
  -MaxTasks 12 `
  -MaxRuntimeMinutes 240 `
  -Json `
  -OutputFile .agent/tmp/dev-queue-189-200-dry-run.json
```

Dry-run writes under ignored `.agent/tmp` and `.agent/campaign-runners`, so it should not dirty the repository. If `git status --short` changes after dry-run, hold the launch and inspect the new paths.

Post-merge launch from clean latest `main`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-dev-queue-189-200.ps1 `
  -GoalPackDir .\goals\dev-queue-189-200 `
  -CampaignId dev-queue-189-200 `
  -MaxSteps 12 `
  -MaxTasks 12 `
  -MaxRuntimeMinutes 240 `
  -Apply `
  -Json `
  -OutputFile .agent/tmp/dev-queue-189-200-runner-report.json
```

Before running with `-Apply`, confirm project control is paused, active tasks are zero, stale leases are zero, no runner lock is active, the worker profile can heartbeat, and the parent PR is no longer draft/manual.

## Goal 188E Heartbeat And Lease Keepalive

Worker heartbeat refreshes the active task lease on the server. During active task execution, `skybridge-edge-worker.ps1` sends a pre-task heartbeat, starts a bounded keepalive job that periodically heartbeats while Codex/validation/PR/CI processing is active, and sends a post-task heartbeat when execution exits. Complete/fail/block still release the lease.

If a child process is still running, status should show the worker with `current_task_id` instead of treating the worker as idle residue. If heartbeat cannot reach the control plane, hygiene surfaces the stale lease with task id, lease id and a `recover-lease` dry-run hint.

Do not recover an active lease until confirming the child process is no longer running. Recovery remains `skybridge-hygiene.ps1 recover-lease -TaskId <id> -LeaseId <id> -Reason <reason>` first in dry-run, then `-Apply` only after review.

## Goal 188G Operator Stop/Resume Drill

For `dev-queue-189-200`, the worker profile is only a readiness target until Goal 190 receives explicit approval. Goal 188G validates control behavior without running the worker loop or creating a campaign-step task.

Two-window workflow:

```powershell
# Window A: watch only
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign-watch.ps1 `
  -CampaignId dev-queue-189-200 `
  -Layout Normal `
  -PollIntervalSeconds 5

# Window B: heartbeat, preflight, reports and controls
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-status.ps1 `
  -Command register-heartbeat `
  -ConfigFile "$HOME\.skybridge\worker.laptop-zenbookduo.json" `
  -Json
```

Safe-pause vs emergency-stop:

- Use `safe-pause -Apply -Reason <reason>` for normal operator holds. It should finish with project control `paused` and `stop_requested=false`.
- Use `emergency-stop -Apply -Reason <reason>` only when the operator needs every runner to stop now. It sets `stop_requested=true`; the operator must press Ctrl+C in any live runner window.
- To recover from emergency stop, run `safe-pause -Apply -Reason <reason>`, then run `resume` without `-Apply` and verify it is still dry-run.

Before any Goal 190 execution:

- worker heartbeat refresh succeeds and `current_task_id` is empty;
- `skybridge-status.ps1 -ActiveOnly` shows active tasks `0`;
- hygiene shows stale leases `0`;
- campaign status shows current step `super-190-campaign-run-report-evidence-ledger`;
- Goal 190 has no linked task ids or PR URLs;
- runner report classifies old Goal 189 failures as historical when applicable.

Do not start Goal 190 until the Pre-190 Acceptance Gate passes.

## Desktop Standby Client

Goal 188H introduces `apps/desktop`, a Tauri v2 tray app for read-only worker/campaign status. It uses the `laptop-zenbookduo` worker profile for status and heartbeat only.

Allowed commands in the MVP:

```powershell
skybridge-status.ps1 -ActiveOnly -Json
skybridge-campaign.ps1 status -CampaignId dev-queue-189-200 -Json
skybridge-worker-status.ps1 -Command status -Json
skybridge-worker-status.ps1 -Command register-heartbeat -Json
```

The last command is exposed as Heartbeat Now and is the only mutation. It must not claim tasks or start the worker loop. The app writes safe local metadata under `.agent/desktop-client/`, which is ignored by git.

The desktop client is a standby surface, not an execution surface. Do not use it to start Goal 190; the Pre-190 Acceptance Gate and explicit operator approval are still required before any bounded execution.
