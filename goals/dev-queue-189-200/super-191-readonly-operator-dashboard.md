```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-191-readonly-operator-dashboard","title":"Read-only Operator Dashboard","order":3,"risk":"medium","task_type":"super-goal","allowed_task_types":["frontend","docs","local-smoke"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-190-campaign-run-report-evidence-ledger"],"expected_outputs":["readonly_dashboard","visual_qa","validation_report"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 191: Read-only Operator Dashboard

## Context

- After the campaign runner and evidence ledger exist, operators need a compact dashboard for current state and recent history.
- This step is read-only so it can improve visibility before any UI mutation workflow is introduced.

## Mission

Add read-only operator UI for project, campaign, step, task, proposal, lease, hygiene, worker, PR, CI, and evidence state.

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

## Phase B: API And Fixture Review

- Identify existing safe read APIs and typed client helpers.
- Add fixture-backed data where needed for local dashboard development.
- Do not add write endpoints in this goal.

## Phase C: Dashboard Views

- Build dense read-only views for project control, campaign progress, steps, tasks, proposals, leases, workers, PR/CI state, and evidence.
- Use existing UI conventions and keep operational layout scannable.
- Clearly distinguish active, blocked, stale, recovered, and completed states.

## Phase D: Read-only Enforcement

- Ensure the route contains no mutation buttons or write forms.
- Ensure network calls from the view use read endpoints only.
- Add disabled-state or no-action fixtures only if useful for later goals.

## Phase E: Responsive And Embed Behavior

- Verify desktop and mobile layouts do not overlap.
- Keep dense tables or lists usable on narrow screens.
- Update dashboard docs.

## Validation Phase

- Run frontend build and focused tests.
- Run local visual smoke coverage where practical.
- Verify no write endpoints are called by the read-only dashboard.

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

- Minimum success: readonly_dashboard is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- screenshot or visual smoke result
- API fixtures used
- read-only enforcement check
- build result
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- readonly_dashboard
- visual_qa
- validation_report

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
