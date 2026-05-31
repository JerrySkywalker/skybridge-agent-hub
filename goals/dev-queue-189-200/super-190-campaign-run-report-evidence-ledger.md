```json
{"schema":"skybridge.super_goal.v1","goal_id":"super-190-campaign-run-report-evidence-ledger","title":"Campaign Run Report and Evidence Ledger","order":2,"risk":"medium","task_type":"super-goal","allowed_task_types":["docs","local-smoke","refactor"],"blocked_task_types":["production_deploy","secret_rotation","server_root_config","github_settings","branch_protection"],"requires":["super-189-ci-guardian-pr-finalizer-hardening"],"expected_outputs":["campaign_report_markdown","campaign_report_json","evidence_ledger"],"advance_gate":{"requires_clean_worktree":true,"requires_no_active_tasks":true,"requires_no_stale_leases":true,"requires_parent_pr_merged":false,"requires_human_approval":true}}
```

# Super 190: Campaign Run Report and Evidence Ledger

Mission: produce Markdown and JSON campaign reports with a durable step ledger, PR/CI/evidence ledger, Hermes gate history, runner state, locks, stop reasons, and final acceptance summary.

Safety boundaries: reports must include metadata only, omit raw logs/prompts/patches, and redact token-looking values. No production deployment or secret mutation is authorized.

Expected outputs: `runner-report` improvements, evidence ledger schema, report smokes, and documentation for reading final run evidence.

Validation requirements: prove JSON output is clean and Markdown report contains all required sections.

Evidence requirements: attach generated report paths, step count, gate decisions, PR links, CI states, and token_printed=false.
