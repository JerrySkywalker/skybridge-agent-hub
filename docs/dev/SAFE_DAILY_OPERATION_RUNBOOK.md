# Safe Daily Operation Runbook

Use this runbook for controlled-mode maintenance.

## Fast Validation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-complete.ps1 -Command status
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-smoke-matrix.ps1 -Command run-fast
```

## Before Release or Infrastructure PRs

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-complete.ps1 -Command gate
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-smoke-matrix.ps1 -Command run-bootstrap-complete
```

Do not run worker loops, start-all, start-queue, resume apply or generic bounded queue apply as part of daily operation.

`token_printed=false`

