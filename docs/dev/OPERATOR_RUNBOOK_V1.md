# Operator Runbook V1

Use this runbook to inspect the controlled release state. Do not start workunits from this release.

Status commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-release.ps1 -Command status
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-release.ps1 -Command readiness
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-release.ps1 -Command release-approval-preview
```

Required safety state:

- `active_tasks=0`
- `stale_leases=0`
- `runner_lock=none`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `execution_enabled=false`
- `queue_apply_enabled=false`
- `no_next_execution_authorized=true`
- `token_printed=false`

Do not run start-all, start-queue, resume `-Apply`, generic bounded queue apply, or worker loops from this release.
