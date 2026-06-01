```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-189-ci-guardian-pr-finalizer-hardening","title":"CI Guardian and PR Finalizer Hardening","order":1,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":[],"expected_outputs":["pr_finalizer_hardening","validation_report","campaign_step_result"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 189: CI Guardian and PR Finalizer Hardening

## Context

- Goal 188 introduced a bounded campaign runner that can create child PRs, watch CI, attach evidence, and advance campaign state. The first unattended development queue depends on that runner making conservative decisions when checks are pending, flaky, failed, or attached to a draft PR.
- The current queue must be safe to run after review. This goal hardens PR finalization and CI guardian behavior before any later queue step relies on it.

## Mission

Harden the PR finalizer and CI guardian so unattended campaign steps can wait for pending checks, classify and retry transient failures once, mark safe draft child PRs ready, merge only eligible low-risk PRs, and repair task or step evidence after a merged child PR.

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

## Phase B: CI State Model

- Review the current PR and check-run collection paths.
- Normalize pending, skipped, cancelled, neutral, timed-out, failed, and successful check states into a small finalizer decision model.
- Keep branch protection and GitHub repository settings read-only.

## Phase C: Bounded Wait And Retry

- Add bounded pending-check wait behavior with clear timeout evidence.
- Classify retryable CI failures separately from real failures.
- Allow at most one automatic retry for transient CI failure signals, and record the reason.

## Phase D: Draft PR And Merge Policy

- Only mark a draft child PR ready when changed files are within expected paths and the task risk is eligible.
- Only merge low-risk eligible child PRs after required checks pass.
- Block auto-merge for unsafe files, high-risk task types, real CI failures, unknown mergeability, or paths outside expected files.

## Phase E: Evidence Repair

- Repair failed task or campaign-step evidence when a child PR later merges successfully.
- Reduce failed/recovered noise in status output without hiding real failed work.
- Record the before and after state in safe metadata only.

## Validation Phase

- Add or update focused PR finalizer smokes for pending checks, transient retry, draft ready, eligible merge, blocked merge, and evidence repair.
- Run PowerShell validation and the smallest relevant package checks.
- Run a dry-run campaign step path that proves no worker loop starts.

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

- Minimum success: bounded pending-check wait is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- PR URL
- changed files
- CI conclusion
- merge commit when present
- finalizer decision
- retry decision
- evidence repair flag
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- bounded pending-check wait
- transient retry classification
- safe PR ready/merge policy
- merged-PR evidence repair
- status output with clearer recovered evidence

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
