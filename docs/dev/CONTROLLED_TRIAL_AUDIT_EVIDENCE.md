# Controlled Trial Audit Evidence

Controlled Trial 221 retains metadata-only evidence under `.agent/tmp/boinc-v1-controlled-trial-221`.

Expected safe reports:

- `trial-result.json`
- `trial-evidence.json`
- `trial-hold-report.json`
- `trial-hold-report.md`
- `trial-audit-report.json`
- `trial-audit-report.md`
- `trial-evidence-retention-report.json`
- `trial-safe-export-report.json`

Required audit events:

- `release_gate_passed`
- `approval_gate_passed`
- `resource_gate_passed`
- `failure_budget_gate_passed`
- `evidence_retention_gate_passed`
- `redaction_gate_passed`
- `controlled_trial_started`
- `task_pr_created`, `controlled_trial_blocked`, or `controlled_trial_failed`
- `human_review_required`
- `no_next_execution_authorized`

The safe export scope is metadata only. Raw prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, raw diffs, authorization headers, cookies, private keys, tokens, and secret-bearing local paths are not persisted or indexed. `token_printed=false`.
