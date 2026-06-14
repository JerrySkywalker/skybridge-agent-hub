# Local Productization Overview

Goal 230 through Goal 232 turns the completed self-bootstrap foundation into a local product preview surface. This does not prove execution again and does not authorize workunit creation, task creation, task claim, queue apply or worker loops.

## Local Profiles

Use `scripts/powershell/skybridge-product-profile.ps1` to inspect profile contracts:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-product-profile.ps1 -Command profile-list -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-product-profile.ps1 -Command profile-validate -Profile full-local-preview -Json
```

Profiles:

- `dev-preview`
- `desktop-only`
- `web-control-plane-preview`
- `supervisor-heartbeat-preview`
- `resident-polling-preview`
- `full-local-preview`

Every profile keeps:

- `execution_enabled=false`
- `queue_apply_enabled=false`
- `remote_execution_enabled=false`
- `arbitrary_command_enabled=false`
- `trusted_docs_auto_merge_enabled=false`
- `token_printed=false`

## Reports

Generated productization reports:

- `.agent/tmp/launch-profiles/product-profile-report.json`
- `.agent/tmp/launch-profiles/local-launch-preview-report.json`
- `.agent/tmp/diagnostics/health-report.json`
- `.agent/tmp/product-readiness/product-readiness-report.json`
- `.agent/tmp/packaging-preview/desktop-packaging-preview.json`
- `.agent/tmp/windows-launcher-preview/windows-launcher-preview.json`

All reports are safe metadata only. Do not persist raw command output, environment dumps, logs, transcripts or secrets.

token_printed=false
