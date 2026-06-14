# Security And Audit Model V1

The v1 controlled release keeps execution disabled by default and relies on safe metadata.

Security requirements:

- No raw prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, raw diffs, Authorization headers, cookies, private keys, tokens, or environment dumps.
- Redaction scan rejects token-like and raw-log fixture payloads.
- Safe export gate must report no raw payload persistence.
- Audit events are metadata-only and include lifecycle facts such as approval preview, heartbeat ingest, evidence indexed, finalizer completed, retry refused, and redaction scan status.
- Human review and finalizer remain required for future task PRs.

Validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-redaction-rejects-token.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-safe-export-gate.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-v1-release-requires-audit.ps1
```
