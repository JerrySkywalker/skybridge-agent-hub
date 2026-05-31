# Master Goal Planner

The master goal planner turns a high-level operator goal into reviewable task proposals. It is preview-first and does not create executable tasks unless an operator explicitly converts a proposal.

For multi-goal operator campaigns, use a Goal Pack instead of one giant master goal. Goal Packs keep ordered Super Goal markdown files local and import them as campaign metadata; campaign advance marks steps ready but does not run workers.

## Concepts

- `master_goal`: the high-level objective, constraints, acceptance criteria and stop conditions.
- `planning_session`: one planner run against current project state.
- `task_proposal`: a candidate task with dedupe key, expected files, acceptance criteria, evidence requirements, required capabilities, risk and rationale.
- `campaign`: an ordered set of Super Goal steps imported from a local Goal Pack.
- `campaign_step`: one sequenced Super Goal markdown file with dependencies, gates and evidence.

Task proposals use this lifecycle:

```text
proposed -> reviewed -> approved -> converted -> executed
         -> rejected
         -> deferred
         -> superseded
         -> blocked_dependency
```

Only approved proposals can be converted. Converted proposals become normal SkyBridge tasks that can be run with `skybridge-run-once.ps1` or `skybridge-guide.ps1`.

Campaigns use:

```text
draft -> ready -> running -> paused -> completed
                 -> held
                 -> failed
                 -> aborted
```

Steps use:

```text
pending -> ready -> running -> completed
                         -> recovered
                         -> failed
                         -> skipped
                         -> held
                         -> needs_human
                         -> blocked_dependency
```

The campaign advance gate is deterministic first. It refuses to advance when active tasks or stale leases exist, dependencies are incomplete, project control is running, required human approval is missing, or required evidence is missing. Super 186 adds Hermes advisory evaluation after deterministic state collection, but deterministic hard blockers remain final.

Hermes gate evaluation returns strict `skybridge.campaign_gate.v1` JSON. Auto-advance requires:

- deterministic gate passes;
- required human approval is present when the step demands it;
- Hermes decision is `advance`;
- `advance-with-gate -Apply` is explicitly used.

The command only advances campaign metadata to the next step. It does not run a worker, create tasks, or execute the next Super Goal.

## Goal Pack Campaigns

Validate and preview the seed campaign locally:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 validate-pack `
  -GoalPackDir goals/bootstrap-mvp

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 import `
  -GoalPackDir goals/bootstrap-mvp `
  -DryRun
```

Apply import only after the target server has campaign endpoints deployed:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 import `
  -GoalPackDir goals/bootstrap-mvp `
  -Apply
```

## Rule-Based Planner

The first planner is deterministic and fixture-friendly:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-plan.ps1 `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-example `
  -Title "Improve operator workflow" `
  -Description "Break the goal into safe reviewable tasks." `
  -DryRun
```

Add `-Apply` to create the master goal, planning session and proposals. Apply does not create executable tasks.

Use `-ConstraintsFile` or `-ConstraintsJson` for multi-value constraints when invoking through `pwsh -File` wrappers. Repeated inline `-Constraints` is still accepted, but JSON/file input avoids positional binding surprises.

## Review Proposals

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command list `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-example

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command show `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id
```

Before approval or conversion, inspect `expected_files`, `risk`, `task_type`, original and normalized capabilities, dependencies, `acceptance_criteria` and `evidence_requirements`.

## Convert A Proposal

Preview conversion first:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command convert `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -DryRun
```

Then approve and convert:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command approve `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Reason "reviewed low-risk docs scope" `
  -Apply

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command convert `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Apply
```

High-risk, deploy, production, secret, GitHub settings, branch protection and server config proposals cannot be auto-approved and should stay manual until the safety policy is expanded.

## Guided Flow

`skybridge-guide.ps1` exposes the same workflow:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-guide.ps1 `
  -Mode plan-preview `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-example `
  -GoalTitle "Improve operator workflow"
```

Preview modes are dry-run by default. `skybridge-guide.ps1 -Mode plan-preview` does not require `-DryRun`; the switch is accepted for compatibility but has no extra effect. Apply modes still require explicit `-Apply`.

Rule-based proposal dedupe keys are stable per master goal and proposal kind. For a master goal id such as `prepare-skybridge-self-bootstrap-supervisor-loop`, examples are:

- `prepare-skybridge-self-bootstrap-supervisor-loop-record`
- `prepare-skybridge-self-bootstrap-supervisor-loop-runbook`
- `prepare-skybridge-self-bootstrap-supervisor-loop-smoke`

Minimum guided modes:

- `plan-preview`
- `plan-apply`
- `proposals`
- `proposal-list`
- `proposal-show`
- `proposal-approve`
- `proposal-reject`
- `proposal-defer`
- `proposal-approved`
- `proposal-pending-review`
- `proposal-convert`
- `proposal-convert-preview`

Hermes CLI can route through the same guide with `-Area operator`.

## Planner Adapter Seam

Planner metadata includes:

- `provider`
- `model`
- `planner_mode`
- `prompt_version`
- `input_state_hash`

Hermes-assisted planning uses:

- `-PlannerMode hermes-preview`: dry-run advisory preview only; it cannot persist proposals or create tasks.
- `-PlannerMode hermes-apply`: planning-record persistence only; it still does not create executable tasks.

For daily Hermes preview, prefer the wrapper:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-preview.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-example `
  -Title "Improve operator workflow" `
  -ConstraintsFile .agent/tmp/hermes-preview-constraints.json `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -OutputFile .agent/tmp/hermes-preview.json
```

Preview output keeps `project_state` as state only and exposes policy-validated proposals in both top-level `proposals` and `planning_session.proposals`. Hermes task types are normalized before policy validation: `smoke` becomes `local-smoke`, `doc` and `documentation` become `docs`, and safe smoke-path `test` proposals can become `local-smoke`. Deploy, production, secrets, GitHub settings, branch protection and server config proposals are blocked or human-gated.

Hermes API must remain private and authenticated. The daily target is direct HTTPS through `https://api.hermes.jerryskywalker.space`; local SSH tunnel mode is a fallback only. See `docs/operations/HERMES_DIRECT_API.md`.

## Safety

- Dry-run is the default.
- `skybridge-plan.ps1 -Apply` creates proposals only, not executable tasks.
- `skybridge-proposal.ps1 approve -Apply` is required before conversion.
- `skybridge-proposal.ps1 convert -Apply` creates a normal queued task only for approved low-risk docs or explicitly approved safe local-smoke proposals.
- Real cloud mutation requires explicit `-Apply`.
- Proposal conversion does not run Codex or start a worker loop.
- Token values are never printed.

This planning layer prepares the self-bootstrap supervisor loop by making task creation reviewable, deduped and evidence-oriented before execution.

## Bounded Supervisor Loop

`skybridge-supervise.ps1` composes planning, proposal selection, proposal conversion and optional `run-once` execution into one bounded loop. It defaults to dry-run and `MaxRounds=1`.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervise.ps1 `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-example `
  -GoalTitle "Improve operator workflow" `
  -DryRun
```

Apply mode requires explicit `-Apply`, selects at most one low-risk proposal per round, and restores project control to paused before exiting. See `docs/orchestrator/SELF_BOOTSTRAP_SUPERVISOR.md` for the stop reasons and decision policy.
