# Goal Pack and Campaign Sequencer

Super Goal 185 adds the foundation for storing multiple Super Goal markdown files as a local goal pack, importing the pack as a SkyBridge campaign, and sequencing its steps without executing workers automatically.

## Goal Pack Format

A pack lives in a directory such as:

```text
goals/bootstrap-mvp/
  campaign.skybridge.json
  super-186-hermes-gate-evaluator-auto-advance.md
  super-187-bootstrap-campaign-mvp-hardening.md
  super-184b-operator-console-dashboard.md
```

`campaign.skybridge.json` uses schema `skybridge.campaign.v1` and records `campaign_id`, `project_id`, source, dependency order, safety policy, default advance gates, stop conditions, and goal markdown paths.

Each Super Goal markdown file stays human-readable and starts with a fenced JSON metadata block:

```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "super-186-hermes-gate-evaluator-auto-advance",
  "title": "Hermes Gate Evaluator and Auto-Advance Pilot",
  "order": 1,
  "risk": "medium",
  "task_type": "super-goal",
  "allowed_task_types": ["docs", "local-smoke", "refactor"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": ["super-185-goal-pack-campaign-sequencer"],
  "expected_outputs": ["draft_parent_pr", "validation_report", "campaign_step_result"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  }
}
```

Validation checks required metadata, unique `goal_id`, unique `order`, parseable advance gates, non-empty markdown body, token-looking strings, and sensitive absolute paths. External completed prerequisites can be listed in `completed_external_dependencies`; campaign step dependencies persisted to the server are intra-pack dependencies only.

## Campaign Model

Campaign states:

```text
draft / ready / running / paused / held / completed / failed / aborted
```

Campaign step states:

```text
pending / ready / running / completed / recovered / failed / skipped / held / needs_human / blocked_dependency
```

Only one campaign step should be running per campaign. A step becomes advanceable only when dependencies are completed, recovered, or skipped. Campaign transitions emit `campaign.*` and `campaign.step.*` events.

## API Surface

The server now exposes campaign endpoints:

- `GET /v1/campaigns?project_id=...`
- `POST /v1/campaigns`
- `GET /v1/campaigns/:campaignId`
- `POST /v1/campaigns/:campaignId/import-goal-pack`
- `GET /v1/campaigns/:campaignId/steps`
- `POST /v1/campaigns/:campaignId/start`
- `POST /v1/campaigns/:campaignId/pause`
- `POST /v1/campaigns/:campaignId/hold`
- `POST /v1/campaigns/:campaignId/resume`
- `POST /v1/campaigns/:campaignId/advance-preview`
- `POST /v1/campaigns/:campaignId/advance`
- `POST /v1/campaigns/:campaignId/steps/:stepId/complete`
- `POST /v1/campaigns/:campaignId/steps/:stepId/fail`
- `POST /v1/campaigns/:campaignId/steps/:stepId/attach-evidence`

Mutation endpoints require worker auth when the server is configured to require worker tokens. `advance-preview` is read-only. `advance` requires `confirm_advance=true` and only marks the next campaign step ready; it does not run a worker.

## CLI

`scripts/powershell/skybridge-campaign.ps1` is dry-run first.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 validate-pack `
  -GoalPackDir goals/bootstrap-mvp

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 import `
  -GoalPackDir goals/bootstrap-mvp `
  -DryRun

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 import `
  -GoalPackDir goals/bootstrap-mvp `
  -Apply

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 advance-preview `
  -CampaignId bootstrap-mvp
```

Mutating commands require `-Apply`: `import`, `start`, `pause`, `hold`, `resume`, `advance`, `complete-step`, `fail-step`, and `attach-evidence`. `complete-step` requires evidence summary or linked task/PR ids. `fail-step` and `hold` require a reason.

## Status Integration

`skybridge-status.ps1` supports campaign visibility:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ShowCampaigns `
  -CampaignLimit 10

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -CampaignId bootstrap-mvp `
  -ShowCampaignSteps
```

JSON output includes `campaign_summary`, `campaigns`, `campaign_steps`, and `campaign_gate_summary`. JSON output remains ANSI-free.

## Deterministic and Hermes Advance Gates

Super 185 introduced deterministic advance gates. Super 186 adds an optional Hermes advisory gate that consumes structured SkyBridge state and returns strict JSON using schema `skybridge.campaign_gate.v1`.

Deterministic policy remains authoritative. Hermes can recommend `advance`, `hold`, `retry`, `ask_human`, or `abort`, but it cannot override hard blockers. Auto-advance requires both a deterministic pass and a Hermes `advance` decision.

Hard holds:

- active queued, claimed, or running tasks exist;
- stale active leases exist;
- project control is running unless explicitly allowed;
- dependencies are not complete/recovered/skipped;
- human approval is required and missing;
- dirty worktree marker is supplied;
- required parent PR merge is missing;
- campaign is failed or aborted.

Soft warnings include recovered tasks, historical blocked tasks, approved-unconverted proposals, and offline workers.

Human approval is explicit. A step with `requires_human_approval=true` can advance only when the operator passes `-HumanApproved` plus a reason. `advance-with-gate` remains dry-run by default and needs `-Apply` to mutate campaign metadata.

Gate commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 gate-preview `
  -CampaignId bootstrap-mvp

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 hermes-gate-preview `
  -CampaignId bootstrap-mvp `
  -UseHermesGate `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1"

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 advance-with-gate `
  -CampaignId bootstrap-mvp `
  -UseHermesGate `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1" `
  -HumanApproved `
  -HumanApprovalReason "Operator approved metadata-only advance."
```

These commands do not run workers and do not create tasks for the next Super Goal.

## Real Cloud Import Result

Super 185 does not deploy unmerged campaign API code. The local fixture and dry-run import are proven. If the live cloud server has not yet deployed the campaign endpoints, cloud import must be skipped and documented as a deployment blocker. No worker execution is part of this goal.

## Seed Pack

The seed pack lives at `goals/bootstrap-mvp/` and contains:

- `super-186-hermes-gate-evaluator-auto-advance.md`
- `super-187-bootstrap-campaign-mvp-hardening.md`
- `super-184b-operator-console-dashboard.md`

Super 186 is the next step and should add Hermes advisory gate evaluation while keeping deterministic vetoes authoritative.

## Super 186 Gate Pilot Boundary

The Super 186 real pilot may advance `bootstrap-mvp` from Super 186 to Super 187 only as campaign metadata. It must not execute Super 187, Super 184B, or any worker loop. If the gate does not produce final decision `advance`, the campaign remains on Super 186 with the hold reason recorded.
