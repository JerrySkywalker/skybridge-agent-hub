# Desktop Resident Worker v1

Desktop Resident Worker v1 is a safe BOINC-style local manager shell for the SkyBridge desktop app. It exposes resident worker status, local resource gate state, completed BOINC v1 alpha state, and preview-only pause/drain/emergency controls.

It does not execute Codex, claim tasks, create workunits, create task PRs, start queues, run generic bounded queue apply, or dispatch arbitrary shell commands. Execution is disabled by default because the resident desktop process must first prove durable local supervision, audit retention, approval flow, and failure budget behavior before it can run work.

## State Model

The desktop fixture uses these schemas:

- `skybridge.desktop_resident_worker.v1`
- `skybridge.desktop_tray_state.v1`
- `skybridge.desktop_worker_control_state.v1`
- `skybridge.desktop_worker_safety_banner.v1`

The default state is:

- `resident_enabled=false`
- `execution_enabled=false`
- `poll_enabled=false`
- `run_apply_enabled=false`
- `queue_apply_enabled=false`
- `resource_gate_required=true`
- `require_operator_approval=true`
- `require_human_review=true`
- `no_next_execution_authorized=true`
- `token_printed=false`

Safe ignored state is written only under `.agent/tmp/local-supervisor/` and `.agent/tmp/desktop-resident-worker/`.

## Operator Checklist

1. Confirm BOINC v1 alpha completed.
2. Confirm `active_tasks=0`, `stale_leases=0`, and `runner_lock=none`.
3. Run the local supervisor status and heartbeat smokes.
4. Confirm Desktop and Web panels show execution disabled.
5. Confirm no enabled run/apply/start controls exist.

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-desktop-resident-worker-status.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-desktop-resident-worker-execution-disabled.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-web-resident-worker-summary.ps1
```
