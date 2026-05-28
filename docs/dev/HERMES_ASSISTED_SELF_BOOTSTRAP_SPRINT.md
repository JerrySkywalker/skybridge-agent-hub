# Hermes-assisted Self-bootstrap Sprint

Date: 2026-05-27

## Goal

Prove a bounded Hermes-assisted multi-round self-bootstrap sprint where Hermes can advise planning/review/evaluation while SkyBridge remains the deterministic control plane and Codex remains the local executor.

## Preflight

- Parent branch: `ai/super-175-hermes-assisted-multiround-self-bootstrap`.
- PR #70: merged before this sprint (`eaf220d`, merged 2026-05-27T06:54:00Z).
- Tag: `v0.43.0-first-dogfood-self-bootstrap-sprint` exists.
- Cloud project: `skybridge-agent-hub` exists.
- Project control before preview: `paused`, `stop_requested=false`, `max_tasks=1`.
- Active queued/running residue: none observed.
- Historical task `task_proposal-d90d09da925d2cf0`: raw `failed`, recovered evidence present, child PR #69 merged.
- Historical task `task_proposal-59a0236fb69800cd`: still `blocked`.
- Worker `laptop-zenbookduo`: `register-heartbeat` succeeded during preflight.
- Worker token and Hermes key values: not printed and not committed.

## Implementation

Added gated Hermes-assisted supervisor foundations:

- planner modes: `rule-based`, `hermes-preview`, `hermes-apply`;
- strict proposal shape for Hermes output;
- proposal validation outputs: `accepted_for_preview`, `accepted_for_execution`, `rejected_duplicate`, `rejected_high_risk`, `rejected_expected_files`, `ask_human`;
- advisory evaluator seam with `hermes_recommendation`, `policy_decision`, `final_decision`, and `reason`;
- default bounded supervisor `MaxRounds=2`;
- per-round active task residue detection;
- fixture smokes for Hermes planner, proposal validation, supervisor preview, and multiround policy.

Hermes cannot execute shell commands or modify files through this path. `tool_execution_mode` is recorded as `disabled`; `raw_response_included=false`; `secrets_included=false`.

## Hermes Preview

- Provider: Hermes.
- Endpoint: configured through local Hermes profile; redacted from committed docs to avoid publishing private endpoint details.
- Model: default model from profile/runtime because `HERMES_MODEL` was not configured.
- Runtime mode: real API attempt.
- Planner mode: `hermes-preview`.
- Prompt version: `hermes-assisted-proposal-v1`.
- Result: stopped before proposal persistence.
- Stop reason: configured Hermes endpoint refused the connection.

No fake preview output was created. The only saved preview artifacts are local snapshots under `.agent/tmp`, which are intentionally untracked.

## Super Goal 176 Hardening

After the tunnel later recovered, a real `hermes-preview` produced useful advisory proposals but exposed workflow gaps: local tunnel fragility, long manual command lines, PowerShell constraints binding risk, inconsistent proposal locations, and Hermes returning `task_type=smoke` where SkyBridge policy expects `local-smoke`.

The hardened preview path is:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-health.ps1 `
  -HermesEnvFile "$HOME\.skybridge\hermes.env.ps1"

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-preview.ps1 `
  -ApiBase https://skybridge.jerryskywalker.space `
  -ProjectId skybridge-agent-hub `
  -MasterGoalId master-goal-hermes-assisted-self-bootstrap-preview `
  -Title "Hermes-assisted SkyBridge self-bootstrap preview" `
  -Description "Use Hermes as an advisory planner to propose safe docs-only or local-smoke tasks for a bounded SkyBridge self-bootstrap sprint." `
  -ConstraintsFile .agent/tmp/hermes-preview-constraints.json `
  -TokenFile "$HOME\.skybridge\secrets\worker-token.txt" `
  -OutputFile .agent/tmp/hermes-preview-176.json `
  -SummaryOutputFile .agent/tmp/hermes-preview-summary.json
```

`-ConstraintsFile` is preferred over repeated inline `-Constraints` when crossing `pwsh -File` boundaries. The wrapper merges inline, file and JSON constraints, validates Hermes health unless skipped, calls `skybridge-plan.ps1 -PlannerMode hermes-preview -DryRun`, and prints a compact proposal table plus counts.

Preview JSON now exposes policy-validated proposals in both top-level `proposals` and `planning_session.proposals`. `project_state` remains state-only and is not the only place proposals appear. Hermes proposal task types are normalized before policy validation: `smoke` becomes `local-smoke`, `doc` and `documentation` become `docs`, and unsafe task types such as deploy, production, secrets, GitHub settings, branch protection and server config remain blocked or human-gated.

Daily operation should move from the SSH tunnel to the direct HTTPS API described in `docs/operations/HERMES_DIRECT_API.md`. Until `https://hermes-api.jerryskywalker.space` is configured and verified, tunnel mode remains a fallback only.

## Apply Sprint

Bounded apply did not run because the real Hermes preview gate did not produce valid low-risk proposals.

- MaxRounds intended: 2.
- Rounds attempted: 0 real apply rounds.
- Rounds completed: 0.
- Selected proposal ids: none.
- Converted task ids: none.
- Child PR URLs: none.
- Child PR CI/merge status: not applicable.
- Evidence repair: not applicable.

## Final State

- Project control restored to `paused`.
- `stop_requested=false`.
- No queued/running task residue was introduced.
- Parent PR remains manual/draft-only.

## Verification

Passed local verification:

- `smoke-supervisor-loop.ps1`
- `smoke-supervisor-policy.ps1`
- `smoke-supervisor-dry-run.ps1`
- `smoke-guide-supervisor-flow.ps1`
- `smoke-master-goal-planner.ps1`
- `smoke-task-proposals.ps1`
- `smoke-proposal-conversion.ps1`
- `smoke-guide-planner-flow.ps1`
- `smoke-skybridge-guide.ps1`
- `smoke-guided-operator-workflow.ps1`
- `smoke-recovered-status-display.ps1`
- `smoke-worker-profile.ps1`
- `smoke-edge-worker-profile-normalization.ps1`
- `smoke-codex-transport-retry.ps1`
- `smoke-hermes-planner-adapter.ps1`
- `smoke-hermes-proposal-validation.ps1`
- `smoke-hermes-assisted-supervisor-preview.ps1`
- `smoke-supervisor-multiround-policy.ps1`
- `validate-powershell.ps1`
- `just check`

## Proof Status

Hermes-assisted multi-round self-bootstrap is not proven yet. The local implementation and fixture-backed policy smokes are in place, but the real Hermes preview stopped at endpoint connectivity before SkyBridge could validate real Hermes proposals.

Next safe retry:

1. Configure or verify direct HTTPS Hermes API, falling back to the SSH tunnel only if necessary.
2. Run `skybridge-hermes-health.ps1`.
3. Re-run `skybridge-hermes-preview.ps1` only.
4. Proceed to a separate Hermes-assisted apply sprint only if preview returns low-risk docs/local-smoke proposals accepted by SkyBridge validation and cloud state remains residue-free.
