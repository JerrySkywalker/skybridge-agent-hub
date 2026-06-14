# Local Runtime Orchestrator

`scripts/powershell/skybridge-local-runtime.ps1` defines a preview-only local runtime skeleton for SkyBridge Agent Hub.

Reports:

- `.agent/tmp/local-runtime/runtime-plan.json`
- `.agent/tmp/local-runtime/runtime-health-report.json`
- `.agent/tmp/local-runtime/runtime-health-report.md`
- `.agent/tmp/local-runtime/local-runtime-report.json`

Schemas:

- `skybridge.local_runtime_orchestrator.v1`
- `skybridge.local_runtime_component.v1`
- `skybridge.local_runtime_plan.v1`
- `skybridge.local_runtime_health.v1`
- `skybridge.local_runtime_report.v1`
- `skybridge.process_health_state.v1`
- `skybridge.local_process_plan.v1`
- `skybridge.local_process_status.v1`
- `skybridge.local_process_blocker.v1`

Safety:

- default mode is dry-run/preview
- no Codex worker start
- no workunit apply
- no task claim
- no unbounded loop
- no service, registry, Startup entry, scheduled task or power setting mutation
- no raw process output, full command transcript or environment dump persistence
- token_printed=false
