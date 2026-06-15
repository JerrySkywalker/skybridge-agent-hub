. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "safe-summary")
Assert-False $summary.claims_task "claims_task"
Assert-TokenPrintedFalse $summary
Complete-Smoke "local-session-no-task-claim"
