```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "dashboard-000-short-slug",
  "title": "Dashboard Control Goal Title",
  "order": 1,
  "risk": "medium",
  "task_type": "dashboard-control-goal",
  "allowed_task_types": ["docs", "frontend", "local-smoke", "test"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": [],
  "expected_outputs": ["read_only_surface", "smoke_evidence"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  }
}
```

# Dashboard 000: Dashboard Control Goal Title

## Context

Describe the operator surface and the queue-control contract it consumes.

## Mission

Add or refine read-only review surfaces without enabling execution controls.

## Hard Safety Boundaries

- Do not expose arbitrary shell execution.
- Do not enable Start One, Start Queue, Resume Apply, worker-loop start, task claim or task execution controls.
- Do not print or persist secrets, raw prompts, raw logs, tokens or Authorization headers.

## Allowed Scope

- Read-only UI panels.
- Fixture-backed preview summaries.
- Smoke tests that inspect source or fixture output.

## Validation

- Run Desktop/Web surface smokes.
- Run focused build/typecheck for the touched app when practical.

## Evidence Requirements

- Screenshot or source-smoke evidence for disabled controls.
- Safe summary with token_printed=false.
- No-execution confirmation.

## Final Campaign State

- can_start_one=false.
- can_start_queue=false.
- queue execution remains disabled.
- token_printed=false.

## No Execution Statement

This dashboard/control goal renders review and preview state only. It does not start queues, claim tasks, create execution tasks or run workers. token_printed=false.
