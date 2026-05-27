# Master Goal Planner

The master goal planner turns a high-level operator goal into reviewable task proposals. It is preview-first and does not create executable tasks unless an operator explicitly converts a proposal.

## Concepts

- `master_goal`: the high-level objective, constraints, acceptance criteria and stop conditions.
- `planning_session`: one planner run against current project state.
- `task_proposal`: a candidate task with dedupe key, expected files, acceptance criteria, evidence requirements, required capabilities, risk and rationale.

Task proposals use this lifecycle:

```text
proposed -> accepted -> converted
         -> rejected
```

Converted proposals become normal SkyBridge tasks that can be run with `skybridge-run-once.ps1` or `skybridge-guide.ps1`.

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

Before conversion, inspect `expected_files`, `risk`, `required_capabilities`, `acceptance_criteria` and `evidence_requirements`.

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

Then accept and convert:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command accept `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Apply

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-proposal.ps1 `
  -Command convert `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -ProposalId proposal-id `
  -Apply
```

High-risk proposals require `-AllowHighRisk` and should stay manual until the safety policy is expanded.

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

Minimum guided modes:

- `plan-preview`
- `plan-apply`
- `proposals`
- `proposal-show`
- `proposal-accept`
- `proposal-convert-preview`

Hermes CLI can route through the same guide with `-Area operator`.

## Planner Adapter Seam

Planner metadata includes:

- `provider`
- `model`
- `planner_mode`
- `prompt_version`
- `input_state_hash`

`-PlannerMode hermes` is present as a disabled seam. Future Hermes integration should build the same compact project state, call Hermes privately, validate the response into task proposals and store only redacted audit metadata. Hermes API must remain private and must not become a public worker dependency.

## Safety

- Dry-run is the default.
- `skybridge-plan.ps1 -Apply` creates proposals only, not executable tasks.
- `skybridge-proposal.ps1 convert -Apply` is the first step that creates a normal queued task.
- Real cloud mutation requires explicit `-Apply`.
- Proposal conversion does not run Codex or start a worker loop.
- Token values are never printed.

This planning layer prepares the self-bootstrap supervisor loop by making task creation reviewable, deduped and evidence-oriented before execution.
