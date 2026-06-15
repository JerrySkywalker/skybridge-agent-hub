# Sandbox Recovery Runbook

Use `scripts/powershell/skybridge-recovery-sandbox.ps1` for fixture-only interrupted install, upgrade, rollback, and recovery previews.

Commands:

- `simulate-interrupted-install`
- `simulate-interrupted-upgrade`
- `simulate-interrupted-rollback`
- `recovery-plan`
- `recovery-preview`
- `report`

Marker files live only under `.agent/tmp/install-sandbox/recovery-markers/`. Cleanup is preview-only unless a future explicit sandbox cleanup command is added.

The recovery report also records orphan lock, stale staging, stale rollback directory, and port conflict metadata without killing processes or mutating the host.

`token_printed=false`
