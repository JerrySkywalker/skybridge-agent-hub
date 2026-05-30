# Queue Hygiene and Recovery

Super Goal 184 adds operator-facing queue hygiene, stale lease detection, proposal reconciliation and colorized status output. The goal is observability and bounded recovery, not automatic requeue.

## Status Color

`skybridge-status.ps1` supports:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -Color
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -NoColor
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ColorMode Auto
```

`Auto` is the default. It enables ANSI color only for likely interactive terminals and respects `NO_COLOR`. JSON output and `-OutputFile` never include ANSI escape codes.

Color is only a visual cue. Plain text still carries the same state names:

- green: ok, completed, recovered, approved, executed;
- cyan: paused or converted;
- yellow: active, queued, claimed, running, blocked, deferred, stale attention needed;
- red: health failure, failed unrecovered, rejected, expired, stale or inconsistent leases;
- dim: none or inactive values.

## Hygiene View

Use `-Hygiene` for a compact governance view:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -Hygiene
```

The JSON shape includes:

- `hygiene_summary`;
- `hygiene_findings`;
- `recommended_actions`.

Useful filters:

- `-StaleOnly`
- `-BlockedOnly`
- `-FailedOnly`
- `-NeedsReview`
- `-NeedsReconciliation`

## Lease Semantics

A lease can be displayed as:

- `active`: active lease for an active task;
- `released`: lease released after terminal task transition;
- `expired`: active lease with `lease_expires_at` before now;
- `stale`: active lease whose worker is stale or offline;
- `abandoned`: operator-marked stale lease;
- `inconsistent`: active lease attached to a task that is no longer queued, claimed or running.

Stale leases are detected and reported by default. SkyBridge does not automatically requeue stale tasks. Operator recovery requires an explicit command, `-Apply` and a reason.

## Task Hygiene Status

Derived task hygiene statuses are:

- `active_ok`;
- `stale_claim`;
- `stale_running`;
- `lease_missing`;
- `lease_expired`;
- `pr_merged_needs_evidence`;
- `recovered_ok`;
- `blocked_historical`;
- `failed_unrecovered`.

These are derived display fields. They do not mutate cloud task state.

## Proposal Reconciliation

Proposal raw lifecycle state is preserved. Status display also derives execution state from the converted task:

- `executed`: `converted_task_id` exists and the task completed or has recovered evidence;
- `converted_unexecuted`: `converted_task_id` exists but the task has not completed or recovered;
- `approved_unconverted`: proposal is approved but has no converted task.

`Proposal Summary` now includes raw counts and derived counts:

- `derived_executed`;
- `converted_unexecuted`;
- `approved_unconverted`.

This fixes the confusing case where raw proposal status remains `converted` even after the associated task completed or recovered.

## Hygiene Command

`skybridge-hygiene.ps1` is a dedicated operator command. It defaults to dry-run/report-only.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hygiene.ps1 audit `
  -ApiBase https://skybridge.jerryskywalker.space `
  -Json
```

Modes:

- `audit`
- `report`
- `stale-leases`
- `stale-tasks`
- `proposals`
- `recover-lease`
- `reconcile-evidence`
- `mark-abandoned`
- `requeue-safe`

Mutation rules:

- `-Apply` is required for any mutation.
- `-Reason` is required for any mutation.
- stale lease recovery uses `/v1/tasks/:taskId/lease-recovery`;
- `requeue-safe` refuses completed, cancelled, non-low-risk and blocked-surface tasks;
- historical `task_proposal-59a0236fb69800cd` is explicitly not recoverable by this command.

Dry-run example:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hygiene.ps1 recover-lease `
  -ApiBase https://skybridge.jerryskywalker.space `
  -TaskId task-id `
  -LeaseId lease-id `
  -Reason "operator reviewed stale lease" `
  -DryRun
```

## Cloud Audit on 2026-05-31

Read-only audit commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase https://skybridge.jerryskywalker.space -Hygiene -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase https://skybridge.jerryskywalker.space -ShowLeases -ShowLocks -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 -ApiBase https://skybridge.jerryskywalker.space -ShowProposals -ProposalLimit 20 -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hygiene.ps1 audit -ApiBase https://skybridge.jerryskywalker.space -Json
```

Findings:

- project control: `paused`;
- `stop_requested`: `false`;
- active queued/claimed/running tasks: `0`;
- active leases: `0`;
- stale leases: `0`;
- released leases: `2`;
- blocked historical tasks: `3`;
- failed unrecovered tasks: `1`;
- recovered tasks: `9`;
- completed tasks: `3`;
- approved unconverted proposals: `2`;
- converted unexecuted proposals: `0`;
- derived executed proposals: `6`;
- deferred proposals: `2`;
- rejected proposals: `0`;
- old proposed proposals: `8`.

Notable findings:

- `task_proposal-59a0236fb69800cd` remains blocked and must not be unblocked automatically.
- `remote-docs-exec-pilot-001` is flagged as `pr_merged_needs_evidence` for operator review.
- `proposal-76496878cf3a15a2` and `proposal-0da654fd64115472` remain approved but unconverted.

No safe reconciliation mutation was performed during Super Goal 184. The audit found no stale active lease and no active task residue.

## Next Step

The next milestone is the Operator Console / Dashboard. It should consume the same derived hygiene fields instead of reimplementing queue-state interpretation in the frontend.
