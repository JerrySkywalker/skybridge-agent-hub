# Backup Restore Preview

`scripts/powershell/skybridge-backup-restore-preview.ps1` previews safe metadata backup and restore.

Reports:

- `.agent/tmp/upgrade-preview/backup-restore-preview.json`
- `.agent/tmp/upgrade-preview/backup-restore-preview.md`

Include:

- safe `.agent/tmp` metadata reports
- release reports
- diagnostics reports
- product readiness reports
- evidence indexes
- audit summaries

Exclude raw logs, prompts, transcripts, stdout/stderr, worker logs, CI logs, environment dumps, secrets, tokens, Authorization headers, cookies, private keys, raw pairing codes, `node_modules`, `target`, and build artifacts unless explicitly safe metadata.

token_printed=false
