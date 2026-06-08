```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "worker-000-short-slug",
  "title": "Worker Service Goal Title",
  "order": 1,
  "risk": "medium",
  "task_type": "worker-service-goal",
  "allowed_task_types": ["docs", "local-smoke", "refactor", "test"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection", "task_execute", "codex_execute"],
  "requires": [],
  "expected_outputs": ["worker_service_state", "readiness_smoke"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  }
}
```

# Worker 000: Worker Service Goal Title

## Context

Describe the bounded worker capability being modeled and the current readiness gate.

## Mission

Improve worker service status, heartbeat or readiness modeling without enabling task execution.

## Hard Safety Boundaries

- Do not start an unbounded worker loop.
- Do not claim or execute tasks.
- Do not run Codex as a worker executor.
- Do not print worker tokens, Authorization headers, raw logs, prompts or private local paths.

## Allowed Scope

- Heartbeat-only fixture or dry-run behavior.
- Readiness contracts and smokes.
- Documentation updates.

## Validation

- Run worker service smokes.
- Prove `can_claim_tasks=false` and `can_execute_tasks=false` unless a later explicit goal changes the boundary.

## Evidence Requirements

- Worker service state output.
- No task claim evidence.
- token_printed=false.

## Final Campaign State

- worker loop not started.
- current task id: none.
- active tasks: 0.
- stale leases: 0.
- token_printed=false.

## No Execution Statement

This worker-service goal may model readiness but must not execute queue steps, claim tasks or run Codex as an executor. token_printed=false.
