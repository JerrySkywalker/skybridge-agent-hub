```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-196-campaign-locking-multi-campaign-queue","title":"Campaign Locking and Multi-campaign Queue","order":8,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-195-manual-goal-queue-management"],"expected_outputs":["campaign_priority_queue","repo_exclusive_lock","stale_lock_recovery"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 196: Campaign Locking and Multi-campaign Queue

## Context

- Goal 188 added campaign runner locks for one campaign. The next reliability step is clearer behavior when multiple campaigns exist or a stale lock remains.
- This must protect the repository from concurrent campaign mutation.

## Mission

Support one active campaign per project, campaign priority queue, cancel/abort, stale campaign lock recovery, and repo-level exclusive lock policy.

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

## Phase B: Lock Model Review

- Review campaign runner lock state, heartbeat, stale detection, and unlock paths.
- Define active, stale, released, cancelled, aborted, and held semantics.
- Do not force-unlock active work.

## Phase C: Multi-campaign Selection

- Add priority ordering for campaigns that are safe to run.
- Ensure only one active campaign per project can be selected.
- Keep current project repo mutation serialized.

## Phase D: Stale Recovery And Abort

- Make stale lock recovery inspection-first and apply-gated.
- Require a reason for unlock, cancel, or abort.
- Record lock owner, heartbeat, age, release reason, and operator decision.

## Phase E: Repo Exclusive Lock

- Add or harden repo-level exclusive lock checks around campaign execution.
- Block execution when another runner or worker owns the repo lock.
- Update runbooks with safe recovery steps.

## Validation Phase

- Prove single active campaign behavior, priority ordering, cancel/abort semantics, stale lock recovery, active lock block, and repo lock exclusion.
- Run campaign runner smokes without applying queue execution.
- Run PowerShell validation.

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

- Minimum success: campaign_priority_queue is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- lock owner
- heartbeat
- expiry
- release reason
- queue decision
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- campaign_priority_queue
- repo_exclusive_lock
- stale_lock_recovery

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
