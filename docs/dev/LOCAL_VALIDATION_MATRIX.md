# Local Validation Matrix

Daily local operation should use safe metadata checks first.

| Area | Command | Expected |
| --- | --- | --- |
| Bootstrap gate | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-complete.ps1 -Command gate` | pass; no next execution authorized |
| Product state layout | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-product-state-layout.ps1` | required schemas documented |
| Product profile contract | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-product-profile-contract.ps1` | all execution toggles false |
| Local launch preview | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-local-launch-preview.ps1` | dry-run preview only |
| Diagnostics | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-diagnostics-health-report.ps1` | safe reports written |
| Diagnostics redaction | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-diagnostics-no-env-dump.ps1` | no env dump or raw logs |
| Packaging preview | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-packaging-preview.ps1` | metadata only |
| Windows launcher preview | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-windows-launcher-preview-dry-run.ps1` | dry-run and no host mutation |
| Web dashboard | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-product-readiness-dashboard-web.ps1` | read-only product readiness route present |
| Desktop dashboard | `pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-product-readiness-dashboard-desktop.ps1` | read-only product readiness card present |

Do not run worker execution, task claim, task creation, workunit creation, task PR creation, generic bounded queue apply, `start-all`, `start-queue`, `resume -Apply` or an unbounded worker loop during this validation.

token_printed=false
