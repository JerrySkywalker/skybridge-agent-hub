# BOINC Manager Control Plane

SkyBridge uses "BOINC-like" to mean an operator control manager that separates visibility, scheduling previews, and future execution authorization. Goal 205A adds the manager vocabulary and surfaces, but execution remains disabled.

## Modes

- Standby: read-only resident worker and queue visibility.
- Armed Preview: preview-only planning; no task claim or execution.
- Start-One Review: historical review of the completed bootstrap trial.
- Bounded Queue Preview: workunit queue preview with apply disabled.
- Bounded Queue Apply Disabled: explicit disabled state for queue apply.
- Managed Mode Disabled: future BOINC-like execution is not authorized.
- Emergency Stop: metadata-only stop state for existing safe stop surfaces.
- Completed Bootstrap Trial: badge/reference for `bootstrap-trial-201`.

Every mode carries `mode_id`, `display_name`, `description`, `enabled`, `reason_disabled`, `required_human_action`, `allowed_actions`, `blocked_actions`, `next_safe_action`, and `token_printed=false`.

## Surfaces

Desktop renders a BOINC Manager card alongside resident worker, resource policy, workunit preview, bounded queue readiness, active holds, and the completed bootstrap trial badge. Web renders the same control plane in the Campaign Queue route with worker/workunit/readiness summaries, action matrix, disabled controls, and next safe action.

## Allowed Actions

The manager allows read-only or metadata-only actions: refresh, open logs, view worker, view workunits, view task PR, view finalizer report, safe pause metadata, and safe stop metadata.

## Blocked Actions

The action matrix disables start-one apply, start-queue apply, bounded queue apply, start-all, resume execution, worker claim, task execution, and auto merge. Disabled buttons must show a reason and must not expose active execution controls.

Bounded queue readiness remains:

```text
can_start_bounded_queue=false
start_bounded_queue_apply_available=false
```

Future bounded queue apply requires a later explicit goal that updates the readiness contract, authorization gate, validation smokes, and UI copy.

## CLI

Read-only script:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-manager.ps1 -Command status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-manager.ps1 -Command safe-summary -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-manager.ps1 -Command action-matrix -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-manager.ps1 -Command mode-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-manager.ps1 -Command operator-guidance -Json
```

## Validation

Focused 205A smokes:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-manager-state-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-manager-mode-preview.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-manager-action-matrix.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-manager-safe-summary.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-manager-execution-disabled.ps1
```
