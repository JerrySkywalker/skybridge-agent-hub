```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-200-controlled-goal-draft-review-import","title":"Controlled Goal Draft Review and Import","order":12,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","frontend","docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-199-hermes-goal-draft-generator"],"expected_outputs":["draft_review_queue","controlled_import","review_smokes"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 200: Controlled Goal Draft Review and Import

## Context

- Goal 199 creates proposed goal drafts only. Goal 200 adds controlled review and import so generated drafts can become queue items only after explicit review.
- This is still not an execution goal. Imported goals require later review before execution.

## Mission

Create a review queue for generated goals with approve, reject, edit, and import flows. Low-risk docs-only drafts may be semi-automatic only after explicit policy; medium/high risk requires human approval.

## Global Safety Boundaries

- Do not print tokens, secrets, credentials, cookies, private keys, raw authorization headers, or secret-bearing local paths.
- Do not mutate GitHub repository settings, branch protection, Actions secrets, environments, or organization settings.
- Do not modify production, server-root, DNS, OpenResty, Authelia, 1Panel, Docker daemon, or Hermes server configuration unless a later goal explicitly allows a bounded change.
- Do not deploy to production, rotate secrets, weaken authentication or authorization, or upload raw command output by default.
- Keep dry-run as the default where an operation can mutate external state.
- Do not run an unbounded worker loop; use bounded, local, fixture, or dry-run validation unless the goal explicitly authorizes apply-mode execution.
- Generated goals require review before import.
- Imported goals require review before execution.
- No auto-import and no auto-execution are allowed.

## Phase A: Preflight

- Run `git status --short` and confirm the working tree is clean before implementation.
- Confirm the current branch is the goal branch for this work, not `main`.
- Run or review the smallest relevant project-control status command and confirm active tasks are zero before any apply-gated operation.
- Run or review hygiene status and confirm stale leases are zero before any apply-gated operation.
- Check for local runner or campaign locks that could indicate another active runner.
- If active tasks, stale leases, active runner locks, or unexpected project-control running state are present, stop and report instead of continuing.

## Phase B: Review Queue Model

- Define draft states such as proposed, reviewed, approved, rejected, edited, imported, and superseded.
- Record reviewer decision, reason, risk, and edited content hash.
- Keep all decisions auditable.

## Phase C: Edit And Approval Flow

- Allow safe edits before import and recompute hashes after edits.
- Require human approval for medium/high-risk drafts.
- Reject drafts that cross hard safety boundaries.

## Phase D: Controlled Import

- Import only approved drafts through an explicit dry-run-first command.
- Validate order, dependencies, duplicate ids, and manifest changes before apply.
- Do not execute imported goals and do not create campaign-step-derived tasks.

## Phase E: UI Or CLI Review Surface

- Add a CLI or dashboard workflow for review, approve, reject, edit, and import preview.
- Show exact diff and risk before import.
- Document post-Goal-200 acceptance workflow.

## Validation Phase

- Prove approve, reject, edit, import dry-run, risk gating, dependency validation, and duplicate detection.
- Prove imported goals are not executed.
- Run local smokes only and PowerShell validation.

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

- Minimum success: draft_review_queue is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- reviewer decision
- review reason
- edited hash
- import result
- risk level
- remaining human approvals
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- draft_review_queue
- controlled_import
- review_smokes

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
