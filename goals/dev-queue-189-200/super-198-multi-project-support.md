```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-198-multi-project-support","title":"Multi-project Support","order":10,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-197-multi-worker-readiness"],"expected_outputs":["project_profiles","project_policy","multi_project_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 198: Multi-project Support

## Context

- SkyBridge Agent Hub should eventually supervise multiple repositories, but each project needs explicit profiles and policy.
- This goal adds project-level configuration without production deployment or secret-bearing configuration.

## Mission

Add project profiles for repo path, default branch, validation command, worker profile, goal pack, allowed paths, and CI policy per project.

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

## Phase B: Profile Schema

- Define a project profile schema for repo path, default branch, validation commands, worker selection, goal pack defaults, allowed paths, and CI policy.
- Reject secret-looking fields and sensitive paths.
- Keep production deploy settings out of scope.

## Phase C: Loader And Validation

- Add a loader with clear missing/invalid profile errors.
- Validate default branch, repo path, allowed paths, and command shape.
- Prefer dry-run validation for project onboarding.

## Phase D: Project Selection

- Wire project profile selection into relevant CLI paths where safe.
- Ensure commands do not accidentally operate on the wrong repository.
- Record selected project and profile hash in dry-run output.

## Phase E: Onboarding Docs

- Document how to onboard a second project.
- Document required fields, optional fields, and forbidden fields.
- Document validation and rollback steps.

## Validation Phase

- Prove missing profile, invalid profile, secret-looking field, disallowed path, default branch mismatch, and worker selection behavior.
- Run local profile smokes only.
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

- Minimum success: project_profiles is implemented or safely documented with focused validation, and no hard safety boundary is crossed.
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

- project id
- profile hash
- selected repo path
- validation command
- policy summary
- token_printed=false
- no secret printing
- no GitHub settings or branch protection changes
- no production/server-root/DNS/OpenResty/Hermes mutation outside explicit bounded scope

## Expected Outputs

- project_profiles
- project_policy
- multi_project_docs

## Non-goals

- Do not execute Goal 189-200 as part of authoring or validation unless a separate reviewed launch goal explicitly permits it.
- Do not create campaign-step-derived tasks while preparing or validating this goal pack.
- Do not weaken existing safety checks to make validation pass.
