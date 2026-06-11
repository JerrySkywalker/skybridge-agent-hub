# Repeatable One-at-a-time Managed Mode

Repeatable one-at-a-time managed mode is the successor to Managed Mode Pilot 208. It keeps the same safety shape: one low-risk workunit, one task, one claim, one Codex execution, one task PR, then a stop for human review.

It is not the full BOINC queue. General bounded queue apply remains disabled, multi-workunit execution remains unavailable, and Desktop/Web surfaces are read-only.

## Registry Model

The registry command is:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command registry -Json
```

It returns:

- `skybridge.managed_mode_run_registry.v1`
- `skybridge.managed_mode_run_record.v1`
- `skybridge.managed_mode_sequence_policy.v1`
- `skybridge.managed_mode_completed_workunit_archive.v1`

Each record stores the run id, sequence number, source workunit id, task id, worker id, task type, risk, allowed paths, state, PR URL/state, finalizer evidence path, evidence hash, timestamps, and `token_printed=false`.

Managed Mode Pilot 208 is archived as completed from `.agent/tmp/managed-mode-pilot-208/finalizer-evidence.json`. The next preview allocates `managed-mode-run-209`.

## Sequence Policy

The sequence policy is deliberately narrow:

- `max_open_runs=1`
- `max_workunits_per_run=1`
- `max_tasks_per_run=1`
- `max_claims_per_run=1`
- `max_codex_executions_per_run=1`
- `max_prs_per_run=1`
- `require_human_review=true`
- `stop_on_pr_created=true`
- `general_bounded_queue_apply_enabled=false`
- `one_at_a_time_run_apply_enabled=false`
- `token_printed=false`

The registry refuses to allocate a new executable run when a completed run id is reused, another run is open, a prior managed-mode task PR is open, active tasks or stale leases exist, or a runner lock is present.

## Future Run Allocation

Preview the next run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command next-run-preview -Json
```

Check the gate:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-run.ps1 -Command next-run-gate -Json
```

In 209A, `run-apply` remains disabled by default. A future goal must explicitly authorize a single run apply, and the gate must still pass at execution time.

## Finalizer Closure

A run that creates a task PR enters `held_waiting_human_pr_review`. A later finalizer goal is responsible for confirming human review and PR state, writing finalizer evidence, and closing the run as `completed`.

The 209B pilot intentionally stops after task PR creation and does not run finalizer apply.

## Operator Surfaces

BOINC manager safe summary now reports:

- `managed_mode_pilot_208=completed`
- `next_mode=repeatable one-at-a-time preview`
- `general_bounded_queue=disabled`
- next safe action: run one explicitly authorized low-risk docs/local-smoke workunit

Desktop and Web expose read-only repeatability panels with completed runs, next run preview, open hold status, apply disabled reason, and next safe action. They do not expose active execution buttons.

## Validation Commands

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-registry-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-archives-208-completed.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-allocate-next-209.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-prevents-duplicate-open-run.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-prevents-reuse-completed-run.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-prevents-when-active-task.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-prevents-when-stale-lease.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-general-bounded-queue-disabled.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-one-at-a-time-gate.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-run-token-printed-false.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-managed-mode-run-registry-panel.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-web-managed-mode-run-registry-panel.ps1
```
