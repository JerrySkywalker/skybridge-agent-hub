```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-197-multi-worker-readiness","title":"Multi-worker Readiness","order":9,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-196-campaign-locking-multi-campaign-queue"],"expected_outputs":["worker_capability_matrix","routing_policy","readiness_smokes"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 197: Multi-worker Readiness

Mission: add worker capability matrix, labels, availability score, routing policy, Windows/Linux distinction, and `max_parallel_per_repo=1` enforcement.

Safety boundaries: do not enable true parallel repo mutation; keep one task per repo until locking is proven.

Expected outputs: capability/routing model, status display updates, smokes, and worker profile docs.

Validation requirements: test routing decisions for online/offline/stale workers, OS labels, capability mismatch, and repo parallelism block.

Evidence requirements: record selected worker, route reason, max parallel decision, and rejected workers.
