# Safe Export Gate

The safe export gate is a release-readiness contract that decides whether generated metadata can leave local ignored evidence directories.

## Contract

`skybridge.safe_export_gate.v1` requires:

- `safe_to_export`
- `raw_prompt_persisted=false`
- `raw_transcript_persisted=false`
- `raw_stdout_persisted=false`
- `raw_stderr_persisted=false`
- `raw_logs_persisted=false`
- `authorization_persisted=false`
- `token_printed=false`

## Boundary

The gate allows safe hashes, safe PR URLs, safe relative paths, schema names, counts, classifications, and concise operator-readable summaries. It blocks raw logs, raw prompts, raw transcripts, raw command output, raw diffs, secrets, token-bearing headers, private keys, cookies, and environment dumps.

## Commands

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-audit-trail.ps1 -Command safe-export-gate
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-safe-export-gate.ps1
```

