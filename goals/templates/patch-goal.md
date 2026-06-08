```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "patch-000-short-slug",
  "title": "Patch Goal Title",
  "order": 1,
  "risk": "low",
  "task_type": "patch-goal",
  "allowed_task_types": ["docs", "local-smoke", "refactor", "test"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": [],
  "expected_outputs": ["patch", "validation_report"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  }
}
```

# Patch 000: Patch Goal Title

## Context

Describe the narrow defect, regression or follow-up being patched.

## Mission

Apply the smallest reviewable fix and prove it with focused validation.

## Hard Safety Boundaries

- Do not print or persist secrets, raw prompts, raw stdout/stderr, private keys, cookies or Authorization headers.
- Do not weaken auth, remove tests only to pass checks, mutate production settings or change branch protection.
- Do not execute campaign steps, claim tasks or start worker loops.

## Allowed Scope

- Targeted code and test changes related to the patch.
- Documentation updates when behavior changes.

## Validation

- Reproduce or fixture the defect when possible.
- Run focused tests and any relevant smoke.

## Evidence Requirements

- Failing/passing validation summary.
- Changed files.
- Residual risk and rollback note.

## Final Campaign State

- Queue execution remains disabled.
- active tasks: 0.
- stale leases: 0.
- token_printed=false.

## No Execution Statement

This patch goal does not start queues, run Codex as a worker executor, claim tasks or create campaign-step-derived execution tasks. token_printed=false.
