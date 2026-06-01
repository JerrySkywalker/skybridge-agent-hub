# Self-Bootstrap Supervisor

The self-bootstrap supervisor is a bounded plan-run-observe-decide loop. It is not an always-on worker daemon and it does not replace operator review.

Campaign sequencing now sits above the supervisor. A campaign step may later invoke a supervisor run, but campaign advance only marks ordered Super Goal steps ready; it does not run workers. Super 186 adds a Hermes advisory gate for metadata-only advance, with deterministic policy still acting as the final veto.

Super 187 hardens the campaign layer as a restartable MVP. Campaign resume, retry, skip and hold decisions are campaign metadata operations first; they must inspect current server state, task leases, repo locks and campaign events before deciding whether a later supervisor or worker run is safe.

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

Campaign advance uses a narrower deterministic gate:

- active tasks hold the campaign;
- stale leases hold the campaign;
- running project control holds the campaign unless explicitly allowed;
- incomplete dependencies hold the campaign;
- required human approval returns `ask_human`;
- dirty worktree markers hold the campaign;
- missing required parent PR merge holds the campaign when requested.

Super 186 adds Hermes advisory evaluation through `skybridge-campaign.ps1 hermes-gate-preview` and `advance-with-gate`. Hermes must return strict `skybridge.campaign_gate.v1` JSON. The final decision records `deterministic_decision`, `hermes_decision`, `final_decision`, hard blockers, warnings, human approval state, `input_state_hash` and prompt version.

Hermes can recommend a hold or advance, but cannot override deterministic blockers. `advance-with-gate` is dry-run by default, requires `-Apply` for metadata mutation, and must not start workers or create tasks for the next Super Goal.

Campaign resume uses the same conservative state source. An interrupted operator session should resume only after re-reading the campaign, current step, recent campaign events, project control, active tasks, stale leases and latest evidence. Resume may recover a stale campaign lock with `-Apply` and a reason, but it must not automatically re-run the current step.

Campaign step execution is explicit and task-backed. `skybridge-campaign.ps1 execute-preview` builds the candidate task payload from the current step markdown and safety metadata without mutation. `execute-step -Apply` creates one queued task and links it to the campaign step; it does not run the worker by itself. The resulting task must still pass the normal lease-backed worker path, repo lock, dirty tree guard, active PR guard, branch collision guard, CI, merge policy and evidence repair rules.

Super 187 proved this flow for `bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening`: the executor created `campaign-step-super-187-bootstrap-campaign-mvp-hardening-20260531100053`, the worker acquired lease `lease_chdDfMPI1SEIgonHR-hzv`, child PR #92 passed checks and merged, recovered evidence was attached, and `advance-with-gate -Apply` moved the campaign metadata to Super 184B ready without executing Super 184B.

Step retry, skip and hold are distinct supervisor inputs:

- retry preserves previous evidence, increments an attempt record and requires a retry reason plus validation target;
- skip requires evidence that the omitted step is superseded, unnecessary or manually accepted;
- hold requires an owner, reason and next review condition.

Skipped or recovered campaign steps can satisfy dependencies only when the evidence is present in the campaign step event log.

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
- Super 187 adds the restartable campaign MVP contract. Campaign locks are separate from task leases and local repo locks. One active campaign per project is the default, with explicit override evidence required for exceptions. Campaign event logs should record advance previews, blocked advances, retries, skips, holds, evidence attachments and export reports using bounded redacted payloads.

This supervisor prepares the dogfood self-bootstrap sprint by connecting the existing planner, proposal review, task conversion, one-shot worker execution and recovered evidence semantics into one bounded operator workflow.

## Goal 188 Runner Commands

The autonomous campaign runner is the next layer above the bounded supervisor. It uses the existing campaign step executor, lease-backed worker flow, PR finalizer, evidence repair and gate evaluator, but owns campaign-level state and a campaign lock so only one active runner can control a project campaign by default.

Use `skybridge-campaign.ps1 run-next` for a single-step execution, `run-until-hold` for unattended execution until a hold or limit, and `run-until-complete` only for a bounded campaign that is already approved for completion. `resume` inspects existing task, PR and evidence state before creating anything new. `runner-status` and `runner-report` are read-only inspection commands.

Runner mutations remain dry-run by default. `runner-unlock` requires `-Apply` and a reason, and stale locks block automatic execution until inspected. The runner never overrides deterministic hard vetoes for active task residue, stale leases, unsafe paths, missing evidence, real CI failures, unapproved high-risk task types or uncertain Hermes gate output.
