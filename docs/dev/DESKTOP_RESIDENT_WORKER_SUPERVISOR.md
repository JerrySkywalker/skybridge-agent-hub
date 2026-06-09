# Desktop Resident Worker Supervisor

Goal 203A adds a BOINC-style resident manager foundation for SkyBridge Desktop. It is a visibility and local-policy layer only.

## Current Capabilities

- Tray presence is represented by `skybridge.desktop_resident_state.v1`.
- Worker supervisor metadata is represented by `skybridge.local_worker_supervisor_state.v1`.
- Local resource policy metadata is represented by `skybridge.local_resource_policy.v1`.
- Execution guard metadata is represented by `skybridge.local_execution_guard.v1`.
- Desktop and Web render resident, supervisor and policy summaries from safe fixtures/report state.
- `scripts/powershell/skybridge-local-resource-policy.ps1` supports `status`, `preview` and `safe-summary`.

## No-Execution Boundary

Goal 203A does not enable background execution.

- no task claim;
- no task execution;
- no Codex worker execution;
- no queue apply;
- no start-all control;
- no arbitrary shell control;
- no powercfg mutation;
- `token_printed=false`.

The only local mutation that remains in the desktop app is the pre-existing heartbeat-only path. Start One, Start Queue, Resume execution and Start All remain disabled.

## Tray Behavior

The desktop app already creates a Tauri tray icon with open, refresh, logs and quit menu items. Close-to-tray and autostart are modeled as disabled metadata in this goal until a later goal safely implements the window-close lifecycle.

## Local Resource Policy

The first policy is preview-only metadata:

- require AC power;
- pause on battery;
- pause below 40 percent battery;
- optional idle requirement currently disabled;
- CPU and memory caps are advisory;
- network required;
- all local hours allowed;
- sleep/lid behavior remains operator-managed.

The PowerShell helper may read battery and memory summaries with Windows-friendly APIs. It must not require admin privileges and must not call `powercfg` mutation commands.

## BOINC-Like Roadmap

Future goals can connect this resident state to bounded workunit queues. That future path should gate execution with resource policy, explicit workunit leases, bounded queue limits and human-review policy. Goal 203A only prepares the local manager surface.

## Validation Commands

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-resident-state-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-worker-supervisor-panel.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-local-resource-policy-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-local-resource-policy-safe-summary.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\validate-powershell.ps1
corepack pnpm check
corepack pnpm -C apps/desktop build
```
