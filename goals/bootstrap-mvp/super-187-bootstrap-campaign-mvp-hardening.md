# Super 187: Bootstrap Campaign MVP Hardening

```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "super-187-bootstrap-campaign-mvp-hardening",
  "title": "Bootstrap Campaign MVP Hardening",
  "order": 2,
  "risk": "medium",
  "task_type": "super-goal",
  "allowed_task_types": ["docs", "local-smoke", "refactor"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": ["super-186-hermes-gate-evaluator-auto-advance"],
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

Harden the campaign sequencer into a restartable MVP with campaign locks, one-active-campaign enforcement, step retry controls, and an auditable step event log.

## Scope

- Add campaign resume semantics after interrupted operator sessions.
- Add a campaign lock separate from per-task repo locks.
- Enforce one active campaign per project unless explicitly overridden.
- Add step retry, skip, and hold workflows with evidence requirements.
- Expand campaign audit and export reports.

## Safety

Keep every mutation dry-run by default and require `-Apply`. Do not run imported Super Goal markdown automatically.
