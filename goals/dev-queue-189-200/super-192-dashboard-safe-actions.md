```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-192-dashboard-safe-actions","title":"Dashboard Safe Actions","order":4,"risk":"medium","task_type":"super-goal","allowed_task_types":["frontend","backend","docs","local-smoke"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-191-readonly-operator-dashboard"],"expected_outputs":["safe_action_ui","confirmation_flow","audit_events"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 192: Dashboard Safe Actions

Mission: add confirmed safe actions for hold, resume, run-next dry-run, advance-preview, approve/defer/reject, attach evidence, and release stale lease dry-run.

Safety boundaries: every mutation requires confirmation and reason; dry-run remains default; high-risk actions remain unavailable.

Expected outputs: action controls, confirmation reason capture, audit payloads, and mutation blocking tests.

Validation requirements: backend/API tests for reason requirements and frontend smoke tests for disabled/high-risk states.

Evidence requirements: record action, reason, dry-run/apply mode, audit event, and no token output.
