```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-196-campaign-locking-multi-campaign-queue","title":"Campaign Locking and Multi-campaign Queue","order":8,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-195-manual-goal-queue-management"],"expected_outputs":["campaign_priority_queue","repo_exclusive_lock","stale_lock_recovery"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 196: Campaign Locking and Multi-campaign Queue

Mission: support one active campaign per project, campaign priority queue, cancel/abort, stale campaign lock recovery, and repo-level exclusive lock policy.

Safety boundaries: stale locks block automatic execution until inspected; unlock requires apply and reason; no force unlock of active work.

Expected outputs: lock APIs or CLI hardening, queue selection policy, stale recovery smokes, and runbook updates.

Validation requirements: prove single active campaign, priority ordering, cancel/abort semantics, stale lock recovery, and repo lock exclusion.

Evidence requirements: record lock owner, heartbeat, expiry, release reason, and queue decision.
