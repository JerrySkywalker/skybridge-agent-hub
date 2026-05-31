```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-194-worker-service-mode","title":"Worker Service Mode","order":6,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-193-notification-attention-loop"],"expected_outputs":["worker_supervisor","heartbeat_loop","service_mode_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 194: Worker Service Mode

Mission: implement a local worker supervisor/service wrapper with heartbeat loop, idle mode, crash recovery, stop/pause files, and log rotation.

Safety boundaries: no production service installation by default, no privileged daemon config, no secret printing, and no unbounded task loop without explicit limits.

Expected outputs: service-mode script, dry-run defaults, supervisor smokes, and runbook updates.

Validation requirements: prove start/stop/pause files, heartbeat, idle behavior, crash recovery fixture, and log rotation.

Evidence requirements: record supervisor status, loop limits, heartbeat result, stop reason, and log paths with local-only raw logs.
