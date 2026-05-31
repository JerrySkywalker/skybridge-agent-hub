```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-195-manual-goal-queue-management","title":"Manual Goal Queue Management","order":7,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-194-worker-service-mode"],"expected_outputs":["goal_templates","manifest_updater","queue_validation"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 195: Manual Goal Queue Management

Mission: add templates, manifest updater, order/dependency checks, hash diff, re-import/update support, and completed campaign archive workflow.

Safety boundaries: do not auto-generate or auto-execute new goals; queue changes are explicit and reviewable.

Expected outputs: goal template files, validation command, manifest update command, archive docs, and smokes.

Validation requirements: validate duplicate ids/orders, dependency errors, hash drift, and clean re-import.

Evidence requirements: record manifest diff, validation result, import mode, and archive target.
