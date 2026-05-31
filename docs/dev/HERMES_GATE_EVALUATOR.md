# Hermes Gate Evaluator

Super Goal 186 adds a Hermes advisory gate for campaign advancement. The gate reviews structured SkyBridge state, but deterministic policy remains the final veto.

## Output Schema

Hermes must return strict JSON only, with no Markdown fences:

```json
{
  "schema": "skybridge.campaign_gate.v1",
  "decision": "advance",
  "confidence": 0.86,
  "campaign_id": "bootstrap-mvp",
  "current_step_id": "bootstrap-mvp:super-186-hermes-gate-evaluator-auto-advance",
  "current_goal_id": "super-186-hermes-gate-evaluator-auto-advance",
  "next_step_id": "bootstrap-mvp:super-187-bootstrap-campaign-mvp-hardening",
  "next_goal_id": "super-187-bootstrap-campaign-mvp-hardening",
  "reasons": ["Structured campaign state was reviewed."],
  "blockers": [],
  "warnings": ["worker_offline"],
  "required_human_actions": [],
  "evidence_reviewed": {
    "active_tasks": 0,
    "stale_leases": 0,
    "failed_unrecovered": 0,
    "blocked_tasks": 3,
    "approved_unconverted_proposals": 2,
    "current_step_status": "ready",
    "linked_prs": [],
    "linked_tasks": [],
    "validation_summary": {},
    "hygiene_summary": {}
  },
  "safety_assessment": {
    "safe_to_advance": true,
    "safe_to_execute_next_step": false,
    "requires_human_approval": true,
    "deterministic_veto_expected": false
  },
  "recommended_next_action": "advance_campaign_metadata_only",
  "raw_notes": "No worker execution."
}
```

The schema name is `skybridge.campaign_gate.v1`. `decision` must be `advance`, `hold`, `retry`, `ask_human`, or `abort`. The prompt records `gate_prompt_version` and the generated input records `input_state_hash`.

## Gate Input

`skybridge-campaign.ps1` builds a redacted `skybridge.campaign_gate_input.v1` object containing campaign state, current and next steps, deterministic advance-preview result, status/hygiene summaries, active task count, stale lease count, failed-unrecovered count, proposal counts, worker summary, Hermes health summary, recent task/proposal summaries, linked PR/task evidence, git branch/commit, dirty marker, and operator human approval marker.

It does not include token values, environment variable values, full event arrays, raw logs, or unredacted secret material.

## Final Decision

The final gate decision is:

1. Deterministic hard blockers always produce `hold` or `abort`.
2. If human approval is required and missing, the final decision is `ask_human`.
3. If deterministic policy passes and Hermes returns `advance`, the final decision may be `advance`.
4. If Hermes returns `hold`, `retry`, `ask_human`, or `abort`, the final decision follows Hermes unless deterministic policy is stricter.

Hard blockers include active tasks, stale leases, stale locks, running project control without explicit campaign-running mode, missing dependencies, failed current step, missing evidence, missing required parent PR merge, and dirty worktree markers.

Warnings do not block by default: recovered tasks, blocked historical tasks, approved-unconverted proposals, and offline workers.

## CLI

Deterministic preview only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 gate-preview `
  -CampaignId bootstrap-mvp
```

Hermes advisory preview:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 hermes-gate-preview `
  -CampaignId bootstrap-mvp `
  -UseHermesGate `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1"
```

Human-approved dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 advance-with-gate `
  -CampaignId bootstrap-mvp `
  -UseHermesGate `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1" `
  -HumanApproved `
  -HumanApprovalReason "Operator approved Super 186 gate pilot; this advance only prepares Super 187 and does not execute it."
```

`advance-with-gate` is dry-run unless `-Apply` is present. It never starts a worker and never creates tasks for the next Super Goal.

## Persistence

Gate results can be attached to the current campaign step:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 attach-gate-evidence `
  -CampaignId bootstrap-mvp `
  -UseHermesGate `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1" `
  -Apply
```

Campaign status now surfaces the latest deterministic decision, Hermes decision, final decision, human approval state, hard blockers, warnings, prompt version, timestamp, and input hash when present.
