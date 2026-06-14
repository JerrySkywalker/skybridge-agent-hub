# Server-approved Workunit Audit Evidence

Goal 225 records safe metadata for the first server-approved run.

- Audit events include gate passes, approval consumption, workunit start, task PR creation or blocked/failure state, human review requirement, and `no_next_execution_authorized`.
- Evidence retention indexes only safe JSON and Markdown artifacts under `.agent/tmp/server-approved-run-225/`.
- Safe export remains metadata-only.
- Raw prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, raw diffs, authorization headers, cookies, private keys, tokens, environment dumps, and secret-bearing local paths are excluded.
- Final reports:
  - `.agent/tmp/server-approved-run-225/workunit-audit-report.json`
  - `.agent/tmp/server-approved-run-225/workunit-audit-report.md`
  - `.agent/tmp/server-approved-run-225/workunit-evidence-retention-report.json`
  - `.agent/tmp/server-approved-run-225/workunit-safe-export-report.json`
- `token_printed=false`.
