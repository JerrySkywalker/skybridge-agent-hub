# Super 186: Hermes Gate Evaluator and Auto-Advance Pilot

```json
{
  "schema": "skybridge.super_goal.v1",
  "goal_id": "super-186-hermes-gate-evaluator-auto-advance",
  "title": "Hermes Gate Evaluator and Auto-Advance Pilot",
  "order": 1,
  "risk": "medium",
  "task_type": "super-goal",
  "allowed_task_types": ["docs", "local-smoke", "refactor"],
  "blocked_task_types": ["production_deploy", "secret_rotation", "server_root_config", "github_settings", "branch_protection"],
  "requires": ["super-185-goal-pack-campaign-sequencer"],
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

Add a Hermes advisory evaluator for campaign advance decisions without replacing deterministic policy vetoes. The evaluator must return strict JSON, never approve over a hard veto, and support dry-run auto-advance previews for a two-step campaign pilot.

## Scope

- Define the Hermes gate evaluator input and output schema.
- Require strict JSON output with explicit decision, confidence, blockers, warnings, and evidence references.
- Keep deterministic policy gates authoritative.
- Add `hermes_gate_enabled=false` by default and an explicit operator-controlled opt-in.
- Run a dry-run two-step campaign pilot; do not execute unbounded worker loops.

## Safety

Do not deploy production infrastructure, rotate secrets, mutate GitHub settings, or auto-advance without explicit operator approval.
