```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-191-readonly-operator-dashboard","title":"Read-only Operator Dashboard","order":3,"risk":"medium","task_type":"super-goal","allowed_task_types":["frontend","docs","local-smoke"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-190-campaign-run-report-evidence-ledger"],"expected_outputs":["readonly_dashboard","visual_qa","validation_report"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 191: Read-only Operator Dashboard

Mission: add read-only operator UI for project, campaign, step, task, proposal, lease, hygiene, worker, PR, CI, and evidence state.

Safety boundaries: no write buttons, no mutation endpoints, no raw tokens, no raw logs, no production deployment.

Expected outputs: read-only views, dense operational layout, responsive behavior, and dashboard docs.

Validation requirements: run frontend build/tests and visual smoke coverage where practical.

Evidence requirements: record screenshots or visual smoke result, API fixtures used, and read-only enforcement checks.
