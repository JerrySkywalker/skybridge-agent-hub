# Two-workunit Trial 226 Audit Report

The final audit artifacts are written under `.agent/tmp/server-approved-two-workunit-trial-226/`.

Required final reports:

- `two-workunit-trial-report.json`
- `two-workunit-trial-report.md`
- `audit-report.json`
- `evidence-retention-report.json`
- `safe-export-report.json`

The report proves:

- Workunit A executed once, created one docs-only PR, merged through scoped trusted-docs gate, and finalized.
- Workunit B executed once only after Workunit A finalizer, created one docs-only PR, merged through scoped trusted-docs gate, and finalized.
- No non-doc PR auto-merge occurred.
- Generic bounded queue apply, remote execution and arbitrary command dispatch stayed disabled.
- Raw prompts, transcripts, stdout, stderr, worker logs, CI logs and token-bearing content were not persisted.
- `token_printed=false`.
