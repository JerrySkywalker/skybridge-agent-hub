```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-194-worker-service-mode","title":"Worker Service Mode","order":6,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-193-notification-attention-loop"],"expected_outputs":["worker_supervisor","heartbeat_loop","service_mode_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 194: Worker Service Mode

## Context

- The current worker loop is useful for bounded execution but needs service-mode ergonomics before longer unattended operation.
- This goal prepares a local supervisor wrapper without installing privileged services or enabling unbounded execution by default.

## Mission

Implement a local worker supervisor/service wrapper with heartbeat loop, idle mode, crash recovery, stop/pause files, and log rotation.

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

## Phase B: Supervisor Design

- Review existing worker loop, run-once, heartbeat, and profile scripts.
- Define a local supervisor state file, stop file, pause file, and bounded runtime options.
- Keep service installation as documentation or dry-run only.

## Phase C: Heartbeat And Idle Loop

- Add a heartbeat loop that can stay idle when no work is available.
- Respect project paused state and operator stop requests.
- Do not start unbounded task execution without explicit limits.

## Phase D: Crash Recovery And Logs

- Record supervisor start, stop, crash, and restart summaries.
- Rotate or bound local logs under ignored .agent paths.
- Keep raw logs local-only and out of telemetry by default.

## Phase E: Runbook Updates

- Document foreground mode, dry-run mode, pause/stop files, restart behavior, and cleanup.
- Document what remains manual for production service installation.

## Validation Phase

- Prove start, stop, pause, heartbeat, idle, crash fixture, and log rotation behavior.
- Run worker profile and worker status smokes that do not execute tasks.
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

- Minimum success: worker_supervisor is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- supervisor status
- loop limits
- heartbeat result
- stop reason
- log path
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- worker_supervisor
- heartbeat_loop
- service_mode_docs

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
