# Super 184B: Operator Console Dashboard

```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "super-184b-operator-console-dashboard",
  "title": "Operator Console Dashboard",
  "order": 3,
  "risk": "medium",
  "task_type": "super-goal",
  "allowed_task_types": ["docs", "frontend", "local-smoke"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": ["super-187-bootstrap-campaign-mvp-hardening"],
  "expected_outputs": ["draft_parent_pr", "validation_report", "campaign_step_result"],
  "advance_gate": {
    "requires_clean_worktree": true,
    "requires_no_active_tasks": true,
    "requires_no_stale_leases": true,
    "requires_parent_pr_merged": false,
    "requires_human_approval": true
  }
}
```

## Mission

Build a read-only operator console for campaign, task, proposal, lease, lock, and queue hygiene visibility. The first dashboard should not expose write buttons.

## Scope

- Show campaign status, current step, next step, blockers, and evidence.
- Show task, proposal, lease, lock, and hygiene summaries.
- Keep the first UI read-only and compatible with existing auth.
- Add screenshots and local UI validation.

## Safety

Do not add mutating dashboard controls in the initial console. Do not weaken authentication or expose secrets.
