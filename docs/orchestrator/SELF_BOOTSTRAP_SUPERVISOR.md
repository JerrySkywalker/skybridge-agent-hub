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

The first selector prefers low-risk proposals whose normalized execution capabilities include `codex`, docs task type, approved review status, not converted/rejected/deferred/superseded, and non-duplicate dedupe keys. `task_type` names the work class; `required_capabilities` names executable tools. Legacy docs proposals that include `required_capabilities=["docs"]` are normalized to `codex`, `git` and `gh` when expected files are under `docs/`. Safe local-smoke proposals under `scripts/powershell/smoke-*.ps1` are normalized to `codex`, `powershell` and `windows` only after the safe-local-smoke gate passes. When several low-risk docs proposals are available, docs/dev record proposals are preferred before runbook follow-ups so the first sprint records the reviewed plan before expanding operator guidance. High-risk proposals, production/deploy/secret/GitHub settings/branch protection/server config proposals and dependency-blocked proposals stay out of real cloud execution.

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

Hermes-assisted preview can also be run without entering the supervisor apply path:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
  -Mode hermes-preview `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-hermes-assisted-self-bootstrap-preview `
  -GoalTitle "Hermes-assisted SkyBridge self-bootstrap preview" `
  -ConstraintsFile .agent/tmp/hermes-preview-constraints.json `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt"
```

Guide modes `hermes-health`, `hermes-preview` and `hermes-preview-summary` are preview-only. They do not convert proposals, do not run workers and do not mutate project control. If the configured Hermes base is not direct HTTPS, the guide reports that tunnel fallback may still be in use.

## Safety

- `MaxRounds` defaults to `1` and must be greater than zero.
- Each round may convert and run at most one proposal.
- Real execution requires `-Apply`.
- Execution uses `skybridge-run-once.ps1 -NoSubmit -Apply`, which passes the selected task id to the edge worker, uses `PollOnce`, fails if that exact target task is not processed, and restores project control to paused.
- The supervisor also attempts to pause project control in `finally`.
- Worker Codex execution classifies websocket, TLS handshake, EOF, connection reset and transport-error messages as Codex transport failures. These failures are retried at most once by default, and persistent failures record `execution_error_class`, `retry_count` and unrecovered evidence instead of retrying indefinitely.
- Hermes planner calls are allowed only in explicit Hermes preview/apply planner modes. The hardened preview wrapper remains dry-run and uses policy-normalized `docs`/`local-smoke` proposals.
- Proposal conversion is approval-gated. `skybridge-proposal.ps1 convert -Apply` refuses non-approved, rejected, deferred, superseded, high-risk and dependency-blocked proposals.
- Worker execution is lease-gated. A claimed task must include an active lease for the selected worker before Codex starts. This intentionally blocks execution against older cloud control planes that can claim tasks but do not yet emit lease metadata.
- Local worker execution also requires a clean worktree, no duplicate active child PR for the task, no colliding task branch and a repo lock under `.agent/locks`.
- Bounded worker loops require explicit `MaxTasks`, idle timeout and stop-on-failure settings. Query status with `-ActiveOnly`, `-RecentTasks`, `-TaskStatus`, `-WorkerId`, `-TaskId`, `-RecoveredOnly` or `-ExcludeRecovered` before starting a batch.
- Super 183 proved a two-task approved proposal batch against the deployed cloud control plane. Both tasks received active leases, passed local workspace guards, created docs-only child PRs, merged after checks passed, released their leases and recorded recovered evidence after the initial draft/pending CI guardian stop.
- Super 184 adds queue hygiene as a pre-run gate. Use `skybridge-status.ps1 -Hygiene` or `skybridge-hygiene.ps1 audit` before any larger batch. Stale leases, stale claimed/running tasks, approved-unconverted proposals and converted-unexecuted proposals are report-only by default. Recovery commands require `-Apply` and `-Reason`; historical `task_proposal-59a0236fb69800cd` must not be unblocked automatically.

This supervisor prepares the dogfood self-bootstrap sprint by connecting the existing planner, proposal review, task conversion, one-shot worker execution and recovered evidence semantics into one bounded operator workflow.
