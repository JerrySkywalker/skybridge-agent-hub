```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-199-hermes-goal-draft-generator","title":"Hermes Goal Draft Generator","order":11,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-198-multi-project-support"],"expected_outputs":["goal_draft_generator","proposed_goal_output","review_required_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 199: Hermes Goal Draft Generator

## Context

- After the queue is safe and project profiles exist, Hermes can help draft future goals. Draft generation must not become import or execution.
- Generated markdown belongs in goals/proposed for human review only.

## Mission

Let Hermes generate candidate Super Goal Markdown saved to goals/proposed for human review only.

## Global Safety Boundaries

- Do not print tokens, secrets, credentials, cookies, private keys, raw authorization headers, or secret-bearing local paths.
- Do not mutate GitHub repository settings, branch protection, Actions secrets, environments, or organization settings.
- Do not modify production, server-root, DNS, OpenResty, Authelia, 1Panel, Docker daemon, or Hermes server configuration unless a later goal explicitly allows a bounded change.
- Do not deploy to production, rotate secrets, weaken authentication or authorization, or upload raw command output by default.
- Keep dry-run as the default where an operation can mutate external state.
- Do not run an unbounded worker loop; use bounded, local, fixture, or dry-run validation unless the goal explicitly authorizes apply-mode execution.
- Generated goal markdown goes to goals/proposed only.
- Generated goals must not be auto-imported.
- Generated goals must not be auto-executed.

## Phase A: Preflight

- Run `git status --short` and confirm the working tree is clean before implementation.
- Confirm the current branch is the goal branch for this work, not `main`.
- Run or review the smallest relevant project-control status command and confirm active tasks are zero before any apply-gated operation.
- Run or review hygiene status and confirm stale leases are zero before any apply-gated operation.
- Check for local runner or campaign locks that could indicate another active runner.
- If active tasks, stale leases, active runner locks, or unexpected project-control running state are present, stop and report instead of continuing.

## Phase B: Draft Schema And Prompt

- Define strict Hermes output schema for proposed Super Goal metadata and body.
- Require safety classification, dependency suggestion, expected files, and review notes.
- Reject markdown that lacks required safety sections.

## Phase C: Proposed Output Handling

- Write generated candidates only under goals/proposed.
- Generate deterministic filenames and content hashes.
- Do not update campaign manifests, do not import drafts, and do not execute generated goals.

## Phase D: Safety Filter

- Reject production deploy, secret rotation, server root config, GitHub settings, branch protection, credential, or broad destructive goals as executable items.
- Flag medium/high-risk drafts for human review.
- Ensure drafts cannot approve themselves.

## Phase E: Fixture Mode And Docs

- Add fixture Hermes output tests for valid, malformed, unsafe, and duplicate drafts.
- Document review workflow and why import is separate in Goal 200.

## Validation Phase

- Fixture Hermes output produces safe proposed Markdown under goals/proposed.
- Unsafe or malformed drafts are rejected and not written.
- No import, campaign update, task creation, or worker execution occurs.

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

- Minimum success: goal_draft_generator is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- prompt version
- draft path
- draft hash
- safety classification
- review status
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- goal_draft_generator
- proposed_goal_output
- review_required_docs

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
