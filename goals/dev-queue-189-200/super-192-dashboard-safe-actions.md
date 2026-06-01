```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-192-dashboard-safe-actions","title":"Dashboard Safe Actions","order":4,"risk":"medium","task_type":"super-goal","allowed_task_types":["frontend","backend","docs","local-smoke"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-191-readonly-operator-dashboard"],"expected_outputs":["safe_action_ui","confirmation_flow","audit_events"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 192: Dashboard Safe Actions

## Context

- The read-only dashboard from Goal 191 gives operators visibility. The next step is a limited action surface for safe, explicit, auditable operations.
- Every mutation must remain deliberate, reasoned, and blocked for high-risk actions.

## Mission

Add confirmed safe actions for hold, resume, run-next dry-run, advance-preview, approve/defer/reject, attach evidence, and release stale lease dry-run.

## Global Safety Boundaries

- Do not print tokens, secrets, credentials, cookies, private keys, raw authorization headers, or secret-bearing local paths.
- Do not mutate GitHub repository settings, branch protection, Actions secrets, environments, or organization settings.
- Do not modify production, server-root, DNS, OpenResty, Authelia, 1Panel, Docker daemon, or Hermes server configuration unless a later goal explicitly allows a bounded change.
- Do not deploy to production, rotate secrets, weaken authentication or authorization, or upload raw command output by default.
- Keep dry-run as the default where an operation can mutate external state.
- Do not run an unbounded worker loop; use bounded, local, fixture, or dry-run validation unless the goal explicitly authorizes apply-mode execution.

## Phase A: Preflight

- Run `git status --short` and confirm the working tree is clean before implementation.
- Confirm the current branch is the goal branch for this work, not `main`.
- Run or review the smallest relevant project-control status command and confirm active tasks are zero before any apply-gated operation.
- Run or review hygiene status and confirm stale leases are zero before any apply-gated operation.
- Check for local runner or campaign locks that could indicate another active runner.
- If active tasks, stale leases, active runner locks, or unexpected project-control running state are present, stop and report instead of continuing.

## Phase B: Action Inventory

- Map each proposed action to an existing CLI/API capability.
- Classify each action as read, dry-run, or apply-gated mutation.
- Do not add production deployment, GitHub settings, branch protection, or secret operations.

## Phase C: Confirmation And Reason Flow

- Require confirmation and an operator reason for every apply-gated mutation.
- Keep dry-run as the default for previewable actions.
- Show exact target ids before submission.

## Phase D: Backend Guardrails

- Enforce reason requirements server-side or in the command wrapper where applicable.
- Emit audit metadata for action, target, reason, actor label, and mode.
- Block high-risk actions even if the UI is manipulated.

## Phase E: UI Integration

- Add action controls to the existing operator surfaces without crowding read-only status.
- Represent disabled and blocked states explicitly.
- Update docs with the safe action matrix.

## Validation Phase

- Run backend/API tests for reason requirements and high-risk blocks.
- Run frontend smokes for disabled states and confirmation flows.
- Verify audit payloads contain no raw tokens or command output.

## Final Status Phase

- Record changed files and commits.
- Record validation commands and results.
- Record final `git status --short`.
- Record project-control state when available: paused/running, active tasks, stale leases, and token_printed=false.
- Record any residual risk or follow-up goal needed for incomplete non-blocking work.

## PR Package Phase

- Keep commits coherent and reviewable.
- Push the branch after validation passes or after failures are clearly documented.
- Open or update the parent PR as draft/manual unless the active goal explicitly authorizes auto-merge.
- Include summary, validation, evidence, risks, rollback notes, and confirmation that no secrets were introduced.

## Success Criteria

- Minimum success: safe_action_ui is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
- Qualified success: all expected outputs are implemented with local or dry-run smokes, docs are updated, and evidence is sufficient for campaign review.
- Ideal success: all expected outputs are implemented, existing relevant checks pass, UX/docs are clear enough for unattended follow-on execution, and residual risk is limited to explicitly documented follow-up work.

## Stop And Hold Conditions

- Active tasks are present.
- Stale leases, active runner locks, or ambiguous lock ownership are present.
- A required validation command fails in a way that would make unattended execution unsafe.
- The implementation would require production/server-root/DNS/OpenResty/Authelia/1Panel/Docker daemon/Hermes mutation outside the explicit scope.
- The implementation would require GitHub settings or branch protection mutation.
- A token, credential, private key, raw prompt, raw command output, or secret-looking value appears in generated output.
- The work would execute a later campaign step or create campaign-step-derived tasks without explicit authorization.

## Evidence Requirements

- action name
- target id
- reason
- dry-run or apply mode
- audit event id or fixture
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- safe_action_ui
- confirmation_flow
- audit_events

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
