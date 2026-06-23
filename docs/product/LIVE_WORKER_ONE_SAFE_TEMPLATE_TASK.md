# Live Worker One Safe Template Task

Mega Goal 332 proves the first live Bootstrap Alpha worker task lifecycle with one purpose-built low-risk task:

```text
server queued task -> local worker preview -> exact-confirmed claim -> start -> fixed safe-local-smoke runner -> complete/fail with sanitized evidence
```

The pilot task id is `live-safe-template-task-332-001`. The worker id is `jerry-win-local-01`.

## Scope

MG332 allows only one live task lifecycle for `safe-local-smoke.v1` through `safe-local-smoke-runner.v1`.

The pilot task is constrained to:

- `project_id=skybridge-agent-hub`
- `risk=low`
- `status=queued` before claim
- `required_capabilities=windows,powershell,node`
- `allowed_paths=.agent/tmp/**`
- blocked paths including `.env`, `secrets/**`, `deploy/**`, `.git/**`, `server-root`, DNS, Cloudflare, OpenResty, Authelia, GitHub settings and production infrastructure

No old queued task may be claimed. The runner rejects completed, cancelled, blocked, claimed, leased, unknown, high-risk, Codex, MATLAB, unsafe-path and non-MG332-residue tasks.

## Commands

Preview task creation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-safe-task-pilot.ps1 -Command preview-create -Json
```

Create the one live pilot task:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-safe-task-pilot.ps1 -Command apply-create -Confirm -ConfirmationText I_UNDERSTAND_CREATE_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY -Json
```

Preview the exact live run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-safe-task-pilot.ps1 -Command preview-run -Json
```

Run the exact live task:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-safe-task-pilot.ps1 -Command apply-run -Confirm -ConfirmationText I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY -Json
```

Report final state:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-live-safe-task-pilot.ps1 -Command report -Json
```

## Evidence

The local runner writes sanitized fixture evidence under `.agent/tmp/live-safe-template-task-332/**` and submits a safe server evidence summary. The full evidence schema is `skybridge.live_safe_template_task_evidence.v1` and includes:

- task id and worker id
- template id and runner id
- started/completed or failed timestamps
- validation status
- changed files under allowed paths only
- `allowed_paths_checked=true`
- `blocked_paths_checked=true`
- `old_task_claimed=false`
- `task_claimed_count=1`
- `codex_run_called=false`
- `matlab_run_called=false`
- `arbitrary_shell_enabled=false`
- `worker_loop_started=false`
- `project_control_unpaused=false`
- `token_printed=false`

## Disabled

MG332 does not enable queue loops, arbitrary task selection, Codex execution, MATLAB execution, PR creation, notification sends, project control unpause, old task requeue or production infrastructure mutation.

Desktop displays the pilot status and evidence fixture, but live apply remains PowerShell-only with exact confirmation.

## Next Steps

MG333 follows this pilot with
[MATLAB Experiment Golden Trial](MATLAB_EXPERIMENT_GOLDEN_TRIAL.md), which is a
separate exact-task MATLAB runner validation for
`live-matlab-golden-task-333-001`. It does not change the MG332 safe-local-smoke
scope or allow arbitrary task claims.
