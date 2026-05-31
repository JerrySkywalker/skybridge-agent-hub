```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-198-multi-project-support","title":"Multi-project Support","order":10,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-197-multi-worker-readiness"],"expected_outputs":["project_profiles","project_policy","multi_project_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 198: Multi-project Support

Mission: add project profiles for repo path, default branch, validation command, worker profile, goal pack, allowed paths, and CI policy per project.

Safety boundaries: project profiles must not contain secrets; production deploy remains blocked.

Expected outputs: profile schema, loader, validation smokes, and docs for onboarding a second project.

Validation requirements: prove missing/invalid profile handling, allowed path policy, default branch validation, and worker selection.

Evidence requirements: record project id, profile hash, selected repo path, validation command, and policy summary.
