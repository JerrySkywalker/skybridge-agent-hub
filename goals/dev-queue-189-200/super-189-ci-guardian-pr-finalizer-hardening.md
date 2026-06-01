```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-189-ci-guardian-pr-finalizer-hardening","title":"CI Guardian and PR Finalizer Hardening","order":1,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":[],"expected_outputs":["pr_finalizer_hardening","validation_report","campaign_step_result"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 189: CI Guardian and PR Finalizer Hardening

Mission: harden the PR finalizer and CI guardian so unattended campaign steps can wait for pending checks, retry transient failures once, mark safe draft PRs ready, merge only eligible low-risk PRs, and repair evidence after a merged child PR.

Safety boundaries: do not deploy, rotate secrets, alter server root config, mutate GitHub settings, weaken branch protection, or print tokens. Auto-merge must stay blocked for unsafe files, real CI failures, high-risk tasks, and paths outside expected files.

Expected outputs: bounded pending-check wait, transient retry classification, safe PR ready/merge policy, merged-PR evidence repair, and reduced failed/recovered noise in status output.

Validation requirements: add or update focused PR finalizer smokes, run PowerShell validation, and run the smallest relevant package checks.

Evidence requirements: record PR URL, changed files, CI conclusion, merge commit when present, finalizer decision, and whether evidence repair was applied.
