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
- `skybridge.campaign_lock.v1`, `skybridge.repo_exclusive_lock.v1` and `skybridge.campaign_priority_queue.v1` report lock ownership, repo exclusivity and deterministic multi-campaign selection without execution side effects.

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
| `campaign_lock_status` | preview/read | lock inspection only |
| `campaign_lock_preview` | preview/read | stale recovery preview only |
| `repo_lock_status` | preview/read | repo-exclusive lock inspection only |
| `repo_lock_preview` | preview/read | active lock blocks execution previews |
| `unlock_stale_campaign_lock` | safe recovery | apply allowed only for stale locks with reason and audit |
| `cancel_campaign_preview` | safe review | reason required; no task creation |
| `abort_campaign_preview` | safe review | reason required; does not kill arbitrary processes |
| `campaign_priority_queue` | read-only | deterministic priority ordering |
| `campaign_select_next_preview` | preview | selection preview only; no mutation |
| `start_one_apply` | armed execution | forbidden until a later reviewed execution gate |
| `start_queue_apply` | armed execution | forbidden until a later reviewed execution gate |
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

Worker offline remains a blocker. Goal 194 adds standby worker service readiness, but standby only reduces operator uncertainty; it does not enable start apply. Goal 195 adds manual goal pack review, hash drift and re-import/archive previews while start actions stay disabled because active tasks are `0`, stale leases are `0`, `can_start_one=false`, `can_start_queue=false`, `can_resume=false`, execution apply is disabled during Goal 195, and `token_printed=false`.

The shared safe summary also carries `goal_pack_id`, `validation_result`, `hash_drift_count`, `dependency_order_status` and `proposed_import_update_action`. These fields are safe to paste when `token_printed=false`.

## CLI

Use the Goal 192 commands through `skybridge-dev-queue-control.ps1`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command control-matrix -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command start-one-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command safe-pause -Reason "operator reason" -Json
```

The CLI defaults to preview/dry-run behavior unless `-Apply` is supplied. In Goal 195, `start-one -Apply`, `start-all -Apply`, `resume -Apply`, `start_one_apply` and `start_queue_apply` are rejected before runner commands can execute.

Fixture queue-control and lock audit output is local-only and ignored:

```text
.agent/tmp/queue-control-audit/
.agent/tmp/campaign-lock-audit/
```

## Deferred Work

Actual start-one/start-queue apply enablement remains deferred until a later reviewed goal adds real arm leases, approval policy, worker readiness, conflict handling and execution-specific audit.
## Goal 197 Routing Readiness Detail

`queue_control_readiness` now includes `routing_readiness` with worker pool counts, capability matrix, selected preview worker, rejected workers, routing policy, and repo parallelism guard.

`can_start_one=false` and `can_start_queue=false` remain hard false in Goal 197. A ready worker means `selected_worker_ready_for_preview_only`, not execution enabled. The contract must continue to distinguish preview selection from task claim or worker execution.
