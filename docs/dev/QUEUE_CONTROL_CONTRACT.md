# Queue Control Contract

Goal 192 adds the queue-control contract foundation. It is not execution enablement.

Desktop, Web, CLI and Server use the same concepts:

- `skybridge.queue_control_intent.v1` describes action, mode, source, actor, campaign, target revision and optional reason.
- `skybridge.queue_control_state.v1` reports campaign state, worker status, active tasks, stale leases, state hash and the action matrix.
- `skybridge.queue_control_action_response.v1` returns `ok`, `mode`, `action`, `allowed`, `blockers`, `warnings`, optional `audit_event_id` and `token_printed=false`.
- `skybridge.queue_control_audit_event.v1` records safe mutations without raw logs, prompts, stdout/stderr, authorization headers, token values, cookies, private keys or secret-bearing paths.
- `run_budget` and `arm_lease` are modeled for future execution gates only. Goal 192 fixture arm leases are preview/schema-only and cannot start work.

## Action Matrix

| Action | Class | Goal 192 behavior |
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
| `start_one_apply` | armed execution | forbidden in Goal 192 |
| `start_queue_apply` | armed execution | forbidden in Goal 192 |
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

Worker offline remains a blocker. For the current campaign state, start actions stay disabled because worker status is `offline`, active tasks are `0`, stale leases are `0`, `can_start_one=false`, `can_start_queue=false`, `can_resume=false`, and `token_printed=false`.

## CLI

Use the Goal 192 commands through `skybridge-dev-queue-control.ps1`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command control-matrix -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command start-one-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command safe-pause -Reason "operator reason" -Json
```

The CLI defaults to preview/dry-run behavior unless `-Apply` is supplied. In Goal 192, `start-one -Apply`, `start-all -Apply`, `resume -Apply`, `start_one_apply` and `start_queue_apply` are rejected before runner commands can execute.

## Deferred Work

Goal 193/194 can add the attention loop and worker service mode. Actual start-one/start-queue apply enablement remains deferred until a future reviewed goal adds real arm leases, approval policy, worker readiness, conflict handling and execution-specific audit.
