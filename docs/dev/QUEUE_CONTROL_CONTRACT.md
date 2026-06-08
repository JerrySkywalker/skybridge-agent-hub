# Queue Control Contract

Goal 192 adds the queue-control contract foundation. Goal 193 adds attention events derived from this contract. Goal 194 adds worker service readiness. None of these goals enables queue execution.

Desktop, Web, CLI and Server use the same concepts:

- `skybridge.queue_control_intent.v1` describes action, mode, source, actor, campaign, target revision and optional reason.
- `skybridge.queue_control_state.v1` reports campaign state, worker status, active tasks, stale leases, state hash and the action matrix.
- `skybridge.queue_control_action_response.v1` returns `ok`, `mode`, `action`, `allowed`, `blockers`, `warnings`, optional `audit_event_id` and `token_printed=false`.
- `skybridge.queue_control_audit_event.v1` records safe mutations without raw logs, prompts, stdout/stderr, authorization headers, token values, cookies, private keys or secret-bearing paths.
- `run_budget` and `arm_lease` are modeled for future execution gates only. Fixture arm leases are preview/schema-only and cannot start work.
- `skybridge.attention_event.v1` derives operator-visible attention items from blockers, worker state, required human action and queue-control audit events.
- `skybridge.worker_service_state.v1` reports bounded standby service state, heartbeat and capability without task claim or execution.

## Action Matrix

| Action | Class | Current behavior |
| --- | --- | --- |
| `refresh_status` | read-only | allowed read |
| `report` | read-only | allowed read |
| `preflight` | read-only | allowed read |
| `heartbeat` | heartbeat-only | low-risk heartbeat only; no task claim |
| `safe_pause` | safe stop/pause | apply allowed only with reason and audit |
| `stop_queue` | safe stop/pause | apply allowed only with reason and audit |
| `emergency_stop` | safe stop/pause | apply allowed only with reason and audit |
| `resume_preview` | preview | preview only; no mutation |
| `start_one_preview` | preview | preview only; no mutation |
| `start_queue_preview` | preview | preview only; no mutation |
| `start_one_apply` | armed execution | forbidden until Goal 195 Start One gate |
| `start_queue_apply` | armed execution | forbidden until Goal 195 Start One gate |
| `start_all` | forbidden | forbidden |
| `arbitrary_shell` | forbidden | forbidden |

## Revision Guard

Preview and apply intents carry `target_revision` or state hash. Fixture smokes reject mismatched revisions. Server previews require a target revision and reject mismatches against the current campaign state hash.

## Operator Surfaces

Desktop and Web show the same Safe Actions / Queue Controls section:

- active/read-only: Refresh, Report, Copy Safe Summary;
- preview-only: Resume Preview, Start One Preview, Start Queue Preview;
- reason-gated safe actions: Safe Pause, Stop Queue, Emergency Stop;
- disabled/forbidden: Start One Apply, Start Queue Apply, Start All, Run Forever, Worker Loop.

Worker offline remains a blocker. Goal 194 adds standby worker service readiness, but standby only reduces operator uncertainty; it does not enable start apply. For the current campaign state, start actions stay disabled because active tasks are `0`, stale leases are `0`, `can_start_one=false`, `can_start_queue=false`, `can_resume=false`, `execution_disabled_until_goal_195` is present, and `token_printed=false`.

## CLI

Use the Goal 192 commands through `skybridge-dev-queue-control.ps1`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command control-matrix -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command start-one-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command safe-pause -Reason "operator reason" -Json
```

The CLI defaults to preview/dry-run behavior unless `-Apply` is supplied. In Goal 193, `start-one -Apply`, `start-all -Apply`, `resume -Apply`, `start_one_apply` and `start_queue_apply` are rejected before runner commands can execute.

Fixture queue-control audit output is local-only and ignored:

```text
.agent/tmp/queue-control-audit/
```

## Deferred Work

Actual start-one/start-queue apply enablement remains deferred until Goal 195 or later adds real arm leases, approval policy, worker readiness, conflict handling and execution-specific audit.
