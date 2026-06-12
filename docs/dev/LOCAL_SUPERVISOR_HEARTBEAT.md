# Local Supervisor Heartbeat

`scripts/powershell/skybridge-local-supervisor.ps1` reports local resident worker status without executing work. It can emit a one-shot heartbeat, preview heartbeat state, inspect lock/resource status, and write safe reports.

## Commands

- `status`
- `heartbeat-once`
- `heartbeat-preview`
- `lock-status`
- `stale-lock-check`
- `resource-status`
- `resident-summary`
- `safe-report`
- `pause-preview`
- `drain-preview`
- `emergency-stop-preview`
- `clear-preview-holds`
- `control-state`
- `action-matrix`
- `evidence-summary`
- `no-execution-gate`

Heartbeat artifacts use `skybridge.local_supervisor_heartbeat.v1` and are written under `.agent/tmp/local-supervisor/`. They include worker id, safe local device id, repo, branch, commit, resource gate status, active tasks, stale leases, runner lock, preview holds, and `token_printed=false`.

The supervisor does not start workers, claim tasks, create workunits, execute Codex, stop processes, mutate Docker, mutate GitHub, dump environment variables, or persist raw logs.

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-supervisor.ps1 -Command status -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-supervisor.ps1 -Command heartbeat-once -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-local-supervisor-heartbeat-once.ps1
```
