```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "recovery-000-short-slug",
  "title": "Recovery Goal Title",
  "order": 1,
  "risk": "medium",
  "task_type": "recovery-goal",
  "allowed_task_types": ["docs", "local-smoke", "refactor", "test"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": [],
  "expected_outputs": ["recovery_report", "validation_report"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  }
}
```

# Recovery 000: Recovery Goal Title

## Context

Describe the failed, blocked or partially complete state and the evidence already available.

## Mission

Recover the repository or campaign metadata to a reviewable, non-executing state.

## Hard Safety Boundaries

- Do not delete user work, force-push main, remove tests just to pass checks or mutate production/server-root/GitHub settings.
- Do not print or persist secrets, tokens, raw prompts, raw stdout/stderr or private local paths.
- Do not start a worker loop, claim tasks or execute queued campaign steps.

## Allowed Scope

- Local fixture repair.
- Metadata-only dry-run previews.
- Documentation of unrecovered risks.

## Validation

- Prove the recovery path is dry-run by default.
- Prove no queue execution or task claim occurred.

## Evidence Requirements

- Recovery summary.
- Before/after validation output.
- Final status and token_printed=false.

## Final Campaign State

- Campaign remains paused or held unless a separate metadata-only goal authorizes a change.
- active tasks: 0.
- stale leases: 0.
- token_printed=false.

## No Execution Statement

This recovery goal repairs review state only. It must not run queue steps, start workers, claim tasks or create campaign-step-derived execution tasks. token_printed=false.
