```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-200-controlled-goal-draft-review-import","title":"Controlled Goal Draft Review and Import","order":12,"risk":"medium","task_type":"super-goal","allowed_task_types":["backend","frontend","docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-199-hermes-goal-draft-generator"],"expected_outputs":["draft_review_queue","controlled_import","review_smokes"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 200: Controlled Goal Draft Review and Import

Mission: create a review queue for generated goals with approve, reject, edit, and import flows. Low-risk docs-only drafts may be semi-automatic after explicit policy; medium/high risk requires human approval.

Safety boundaries: no auto-import of generated goals, no auto-execution, no secret printing, and no GitHub settings or branch protection changes.

Expected outputs: review queue model, CLI/UI workflow, controlled import command, and docs for acceptance after Goal 189-200.

Validation requirements: prove approve/reject/edit/import behavior, risk gating, and dependency/order checks.

Evidence requirements: record reviewer decision, edited hash, import result, risk level, and remaining human approvals.
