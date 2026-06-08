```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "super-000-short-slug",
  "title": "Super Goal Title",
  "order": 1,
  "risk": "medium",
  "task_type": "super-goal",
  "allowed_task_types": ["docs", "local-smoke", "refactor"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": [],
  "expected_outputs": ["reviewable_output", "validation_report"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  }
}
```

# Super 000: Super Goal Title

## Context

Explain the prior campaign state, dependency chain and reason this goal exists.

## Mission

State the smallest complete outcome this goal must deliver.

## Hard Safety Boundaries

- Do not print tokens, Authorization headers, raw prompts, raw stdout/stderr, private keys, cookies or secret-bearing local paths.
- Do not mutate production, server-root, DNS, OpenResty, Authelia, 1Panel, Docker daemon, Hermes, GitHub settings, branch protection or secrets.
- Do not start a worker loop, claim tasks, execute queue steps, create campaign-step-derived tasks or enable queue execution controls.

## Allowed Scope

- Repository-local code, docs, fixture data and smoke tests.
- Dry-run previews and local ignored artifacts.

## Validation

- Run focused smokes for this goal.
- Run the smallest relevant lint/type/test/build check.
- Run final read-only campaign status/report.

## Evidence Requirements

- Commit ids.
- Validation command results.
- Safe preview output with token_printed=false.
- Final campaign state and clean git status.

## Final Campaign State

- current step remains the current goal unless an explicitly reviewed metadata-only advance is authorized.
- active tasks: 0.
- stale leases: 0.
- can_start_one=false.
- can_start_queue=false.
- token_printed=false.

## No Execution Statement

This template is for reviewable authoring only. It must not execute campaign steps, start workers, claim tasks or create campaign-step-derived execution tasks. token_printed=false.
