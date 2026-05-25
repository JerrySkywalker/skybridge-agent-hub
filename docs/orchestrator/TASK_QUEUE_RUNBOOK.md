# Task Queue Runbook

## Implemented

SkyBridge now persists projects, master goals, tasks and task events. Tasks can be created, claimed, started, completed, failed, blocked and requeued through local APIs.

Task statuses:

- `queued`
- `claimed`
- `running`
- `completed`
- `failed`
- `blocked`
- `cancelled`
- `stale`

Each lifecycle operation writes a `task.*` event. Task responses include safe result metadata only.

## Not Implemented Yet

- No full Hermes planner loop.
- No Edge Worker executor.
- No raw prompt storage.
- No command output, patch or secret persistence.
- No public remote execution surface.

## Local Smoke

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-task-state-machine.ps1
```

The smoke verifies:

- queued to claimed to completed;
- queued to claimed to failed to requeued;
- queued to blocked;
- completed tasks cannot be claimed;
- disabled workers cannot claim tasks.

## Agent-Agnostic Boundary

Hermes is a planner adapter that may create tasks later. Codex, OpenCode and manual execution are executor adapters that may claim and complete tasks. GitHub is one possible SCM/CI provider for result links. ntfy is one notification provider for attention routing.

SkyBridge Core owns the durable project, goal, worker, task and event state independent of those adapters.
