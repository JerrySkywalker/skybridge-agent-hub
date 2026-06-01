```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-199-hermes-goal-draft-generator","title":"Hermes Goal Draft Generator","order":11,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-198-multi-project-support"],"expected_outputs":["goal_draft_generator","proposed_goal_output","review_required_docs"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 199: Hermes Goal Draft Generator

Mission: let Hermes generate candidate Super Goal Markdown saved to `goals/proposed` for human review only.

Safety boundaries: generated drafts are not imported, not executed, and cannot approve themselves. Do not generate production deploy, secret rotation, server root config, GitHub settings, or branch protection tasks as executable queue items.

Expected outputs: generator command, strict output schema, proposed directory handling, and review-required docs.

Validation requirements: fixture Hermes output must produce safe proposed Markdown and reject unsafe or malformed drafts.

Evidence requirements: record prompt version, draft path, draft hash, safety classification, and review status.
