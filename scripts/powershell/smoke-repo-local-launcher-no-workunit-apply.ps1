. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "safe-summary")
Assert-False $summary.result.runs_workunit_apply "runs_workunit_apply"
Assert-TokenPrintedFalse $summary
Complete-Smoke "repo-local-launcher-no-workunit-apply"
