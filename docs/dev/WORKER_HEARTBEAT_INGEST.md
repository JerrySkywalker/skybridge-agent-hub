# Worker Heartbeat Ingest

Goal 218 heartbeat ingest accepts safe state summaries only.

Contracts:

- `skybridge.worker_heartbeat.v1`
- `skybridge.worker_resource_gate_report.v1`
- `skybridge.worker_queue_preview_report.v1`
- `skybridge.worker_resident_status.v1`
- `skybridge.worker_ingest_rejection.v1`

The ingest route is `POST /api/workers/:id/heartbeat-ingest`. It stores process-local safe JSON for preview and tests. It does not create tasks, claim tasks, start a worker loop or transmit real secrets.

Accepted fields include worker identity, repo, branch, commit, resident state, resource gate status, blockers, active task count, stale lease count, runner lock, review hold, queue preview, drain/pause state, emergency-stop preview state and timestamp.

Rejected fields include raw logs, stdout, stderr, prompts, transcripts, worker logs, CI logs, GitHub logs, Authorization headers, bearer tokens, private keys, cookies, environment dumps and `token_printed=true`.

Desktop compatibility is represented by `fixtures/server-control-plane/desktop-heartbeat-export.fixture.json`, which matches `skybridge.worker_heartbeat.v1` and keeps execution disabled.

Validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-heartbeat-ingest-safe.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-heartbeat-rejects-raw-logs.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-heartbeat-rejects-raw-prompt.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-heartbeat-rejects-token-printed-true.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-heartbeat-rejects-authorization-header.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-heartbeat-export-fixture.ps1
```
