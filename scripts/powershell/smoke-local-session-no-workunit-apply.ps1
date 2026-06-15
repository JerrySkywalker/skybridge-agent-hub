. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "safe-summary")
Assert-False $summary.runs_workunit_apply "runs_workunit_apply"
Assert-TokenPrintedFalse $summary
Complete-Smoke "local-session-no-workunit-apply"
