# Self-Bootstrap Supervisor

The self-bootstrap supervisor is a bounded plan-run-observe-decide loop. It is not an always-on worker daemon and it does not replace operator review.

## Model

A supervisor run records:

- `supervisor_run_id`
- `project_id`
- `master_goal_id`
- `mode`: `dry-run` or `apply`
- `max_rounds`
- `current_round`
- `status`: `planned`, `running`, `completed`, `blocked`, `failed` or `stopped`
- `stop_reason`
- timestamps

Each round records observed state, selected proposal, selected task, action, decision reason, PR URL, CI status, task status and evidence status when available.

## Preview

Dry-run is the default. This previews planning, proposal selection, conversion shape and the one-shot command without mutating server state:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervise.ps1 `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId prepare-self-bootstrap-supervisor `
  -GoalTitle "Prepare self-bootstrap supervisor" `
  -MaxRounds 1 `
  -DryRun
```

If `-MasterGoalId` is omitted, the command derives a deterministic id from `-GoalTitle`, such as `master-goal-prepare-self-bootstrap-supervisor`.

## Apply

Apply mode can create planning records, accept one selected proposal, convert it to one executable task and optionally run it once:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervise.ps1 `
  -ApiBase https://skybridge.example.com `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId prepare-self-bootstrap-supervisor `
  -GoalTitle "Prepare self-bootstrap supervisor" `
  -WorkerProfile "$HOME\.skybridge\worker.<hostname>.json" `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -MaxRounds 1 `
  -Apply
```

Use `-NoRun` to apply planning and conversion only. Use `-StopAfterPlan`, `-StopAfterProposal` or `-StopAfterConvert` to stop at a review boundary.

## Decision Policy

The deterministic policy can output:

- `continue`
- `stop_completed`
- `stop_no_safe_proposal`
- `stop_worker_unavailable`
- `stop_ci_blocked`
- `stop_task_failed`
- `ask_human`

The first selector prefers low-risk proposals with `required_capabilities` including `codex`, docs task type, not converted/rejected, and non-duplicate dedupe keys. High-risk proposals require `-AllowHighRisk` and should stay out of real cloud execution until the safety policy is expanded.

Recovered task evidence is not blocking: raw `failed` plus `evidence_summary.recovered=true` and `ci_status=passed_after_rerun` is treated as recovered for supervisor decisions.

## Guide Facade

`skybridge-guide.ps1` exposes:

- `supervise-preview`
- `supervise-apply`
- `supervise-status`

Preview remains dry-run. Apply requires explicit `-Apply`.

Hermes CLI routes the same facade through:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area operator `
  -Command supervise-preview `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId prepare-self-bootstrap-supervisor `
  -GoalTitle "Prepare self-bootstrap supervisor"
```

## Safety

- `MaxRounds` defaults to `1` and must be greater than zero.
- Each round may convert and run at most one proposal.
- Real execution requires `-Apply`.
- Execution uses `skybridge-run-once.ps1 -NoSubmit -Apply`, which uses `PollOnce` and restores project control to paused.
- The supervisor also attempts to pause project control in `finally`.
- No Hermes planner call is made in this goal; `PlannerMode` remains `rule-based`.
- Long-running worker loops remain deferred.

This supervisor prepares the dogfood self-bootstrap sprint by connecting the existing planner, proposal review, task conversion, one-shot worker execution and recovered evidence semantics into one bounded operator workflow.
