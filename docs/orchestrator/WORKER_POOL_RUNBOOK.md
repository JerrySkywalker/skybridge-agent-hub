# Worker Pool Runbook

## Implemented

SkyBridge now persists workers and worker heartbeats in SQLite and exposes safe local APIs for registration, heartbeat, listing, detail and enable/disable display state.

Worker status is derived from the latest heartbeat:

- `online`: heartbeat within 2 minutes;
- `stale`: heartbeat within 15 minutes;
- `offline`: no recent heartbeat;
- `disabled`: worker record is disabled.

The worker model is agent-agnostic. A worker can represent manual execution, Codex, OpenCode, a future sidecar or another runtime provider.

## Not Implemented Yet

- No Edge Worker runtime.
- No remote command transport.
- No public Hermes exposure.
- No destructive worker controls.
- No secret storage.

## Local Smoke

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-task-core.ps1
```

The smoke starts a temporary local server, registers a worker, sends a heartbeat and completes a task without real Codex, Hermes or notification delivery.

## Hermes Self-Ordering Preparation

Hermes can later act as a planner adapter that observes worker capacity and creates tasks. The core worker pool is already neutral, so a rule-based planner, manual operator or future planner can use the same state.
