# CLI Control Runbook

`scripts/powershell/skybridge-hermes-cli.ps1` is the first operator CLI for controlling the SkyBridge project loop. It writes neutral project control state through the SkyBridge API and inspects workers/tasks without exposing secrets.

## Project Control

Start or update loop limits:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command start `
  -ProjectId skybridge-agent-hub `
  -MaxTasks 2
```

Pause new work:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command pause `
  -ProjectId skybridge-agent-hub
```

Resume after a pause or sleep recovery:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command resume `
  -ProjectId skybridge-agent-hub
```

Request stop:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command stop `
  -ProjectId skybridge-agent-hub
```

Inspect status:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command status `
  -ProjectId skybridge-agent-hub `
  -Json
```

## Worker And Task Inspection

List workers:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area workers `
  -Command list `
  -Json
```

List project tasks:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area tasks `
  -Command list `
  -ProjectId skybridge-agent-hub `
  -Json
```

Show one task:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area task `
  -Command show `
  -TaskId <task-id> `
  -Json
```

## Control State Fields

Project control state contains:

- `state`: `running`, `paused` or `stopped`;
- `stop_requested`;
- `max_rounds` and `max_tasks`;
- `current_worker_id` and `current_task_id`;
- `loop_task_count`;
- `degraded_reason`, `idle_since` and `stop_reason`;
- `last_error`, `last_notification` and `last_heartbeat`.

## Operator Notes

- The CLI calls SkyBridge APIs; it does not mutate GitHub settings or production infrastructure.
- The CLI does not read or print `HERMES_API_KEY`, notification credentials or local env files.
- `project pause` and `project stop` prevent the loop from starting new tasks. A task that has already been claimed should be inspected through task status and local worker logs.
- Use the Worker Pool and Task Queue pages to see loop state, last heartbeat, task count and degraded/stop reasons.
