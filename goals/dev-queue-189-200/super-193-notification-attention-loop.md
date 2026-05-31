```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-193-notification-attention-loop","title":"Notification and Attention Loop","order":5,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","docs","local-smoke"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-192-dashboard-safe-actions"],"expected_outputs":["notification_rules","ntfy_events","attention_loop_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 193: Notification and Attention Loop

Mission: add ntfy-first notifications for campaign, step, PR, CI, gate, hold, failure, and completion transitions.

Safety boundaries: notification payloads are concise metadata only; do not include raw logs, prompts, command output, patches, tokens, or secrets.

Expected outputs: notification routing rules, smoke fixtures, and operator attention documentation.

Validation requirements: fixture notification smokes must pass with ntfy unavailable and configured cases represented safely.

Evidence requirements: record notification kind, priority, destination status, redaction status, and token_printed=false.
