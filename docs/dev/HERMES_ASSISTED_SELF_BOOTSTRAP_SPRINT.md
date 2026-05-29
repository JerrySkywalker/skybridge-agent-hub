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

Daily operation should move from the SSH tunnel to the direct HTTPS API described in `docs/operations/HERMES_DIRECT_API.md`. Super Goal 177 verified `https://api.hermes.jerryskywalker.space`; tunnel mode remains a fallback only.

## Apply Sprint

Super Goal 177 proved the first Hermes-assisted proposal persistence and single apply sprint. This was intentionally not a multi-round supervisor run.

- Hermes endpoint: `https://api.hermes.jerryskywalker.space`.
- Direct HTTPS: `true`.
- Hermes health: `ok=true`.
- Hermes platform/model: `hermes-agent` health; planner request model recorded as `default`.
- Hermes runtime mode: `server_agent` in health; planner adapter runtime mode `real-api`.
- Planner modes: `hermes-preview` for preflight, then `hermes-apply` for proposal persistence.
- Planner tool execution mode: `disabled` in SkyBridge planner metadata.
- Master goal id: `master-goal-hermes-assisted-self-bootstrap-preview`.
- Persisted planning session: `planning-session-36e4ecc246bc2996`.
- Persisted proposals: 3 docs proposals accepted for execution policy.
- Selected proposal: `proposal-4212a5e1447212c0`, `Update sprint progress after master goal doc merged`.
- Selected dedupe key: `proposal-progress-after-pr69-20260529`.
- Selected expected files: `docs/dev/PROGRESS.md`.
- Converted task id: `task_proposal-4212a5e1447212c0`.
- Worker id: `laptop-zenbookduo`.
- Execution mode: one targeted `PollOnce`; no long-running loop.
- Codex transport retry count: `0`.
- Child PR: [#73](https://github.com/JerrySkywalker/skybridge-agent-hub/pull/73).
- Child PR changed files: `docs/dev/PROGRESS.md` only.
- Child PR CI: AI branch validation, Project check, Docker build server and Docker build web passed.
- Child PR merge: merged with commit `c69aa6c209b61481cb8067bc58e4191faf76309d`.
- Evidence repair: applied because CI Guardian initially failed the task while checks were pending; repaired status is `recovered=true`, `ci_status=passed_after_pending`, `risk_status=low_docs_only`.

The local-smoke proposal was not selected. The historical blocked task `task_proposal-59a0236fb69800cd` was not unblocked or run.

## Final State

- Project control restored to `paused`.
- `stop_requested=false`.
- No queued/running task residue remained after the single apply.
- Selected task `task_proposal-4212a5e1447212c0` is raw `failed` with recovered evidence by design, because CI Guardian observed pending checks before they passed.
- Historical blocked task `task_proposal-59a0236fb69800cd` remains blocked.
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

Hermes-assisted single apply is proven. Hermes direct HTTPS health and preview worked, Hermes apply persisted proposals, SkyBridge selected and converted exactly one low-risk docs proposal, `laptop-zenbookduo` executed exactly one targeted task through PollOnce, child PR #73 passed checks and merged, and evidence repair captured the recovered task state.

Hermes-assisted multi-round apply remains deferred.

Next safe retry:

1. Keep direct HTTPS Hermes health green.
2. Decide whether to retire, re-scope or explicitly unblock `task_proposal-59a0236fb69800cd`.
3. Run another preview before any additional apply.
4. Proceed to a separate Hermes-assisted multi-round apply sprint only after confirming no queued/running residue and keeping `MaxParallel=1`.

## Super Goal 178R Preview 504 Recovery

The first multi-round reliability sprint attempt was blocked before proposal persistence by OpenResty `504 Gateway Time-out` responses from the direct HTTPS `/v1/responses` path. Health and capabilities remained green, and a tiny responses probe succeeded, so the failure is specific to long-running real planner responses.

The repair branch added transient-only Hermes preview retry, compact planner state as the default real preview input, 600 second preview timeout support, and OpenResty diagnosis guidance. No `hermes-apply`, task conversion, worker `PollOnce` or project-control mutation was run. See `docs/dev/HERMES_ASSISTED_MULTIROUND_RELIABILITY_SPRINT.md` for the current recovery status and next server-side action.
