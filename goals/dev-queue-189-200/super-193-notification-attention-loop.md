```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-193-notification-attention-loop","title":"Notification and Attention Loop","order":5,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","docs","local-smoke"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-192-dashboard-safe-actions"],"expected_outputs":["notification_rules","ntfy_events","attention_loop_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 193: Notification and Attention Loop

## Context

- Campaign execution can run unattended only if important transitions reach the operator without requiring constant dashboard polling.
- SkyBridge is ntfy-first, but notification behavior must be safe when ntfy is unavailable or unconfigured.

## Mission

Add ntfy-first notifications for campaign, step, PR, CI, gate, hold, failure, and completion transitions.

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

## Phase B: Event And Rule Mapping

- Map campaign and runner transitions to normalized notification events.
- Classify priority for hold, failure, blocked, completion, and attention-needed states.
- Keep routine progress low-noise.

## Phase C: Safe Payloads

- Use concise metadata only: ids, titles, status, PR URL, CI conclusion, and next action.
- Never include raw logs, prompts, patches, stdout, stderr, command output, tokens, or secrets.
- Apply existing redaction helpers to notification payloads.

## Phase D: Provider Behavior

- Ensure fixture and unconfigured ntfy paths record skipped placeholders safely.
- Ensure configured provider paths can be smoke-tested without printing credentials.
- Record destination status without leaking topic tokens.

## Phase E: Attention Docs

- Document which transitions page the operator.
- Document muted or low-priority transitions.
- Document recovery behavior after notification provider failure.

## Validation Phase

- Run fixture notification smokes with ntfy unavailable.
- Run configured-case coverage through safe fixtures or redacted local configuration when available.
- Run token-looking text checks on notification JSON fixtures.

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

- Minimum success: notification_rules is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- notification kind
- priority
- destination status
- redaction status
- provider result
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- notification_rules
- ntfy_events
- attention_loop_docs

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
