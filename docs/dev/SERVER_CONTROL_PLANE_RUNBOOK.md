# Server Control Plane Runbook

The server control plane remains preview-only for v1. It can model worker registration, pairing preview, heartbeat ingest, and operator approval preview. It must not send arbitrary shell commands and must not cause a worker to run Codex.

Inspect:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-worker-pairing-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-heartbeat-ingest-safe.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-approval-does-not-execute.ps1
```

The server rejects raw logs, raw prompts, Authorization headers, token-shaped payloads, and `token_printed=true`.
