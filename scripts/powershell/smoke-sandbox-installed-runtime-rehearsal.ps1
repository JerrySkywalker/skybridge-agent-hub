. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-sandbox-installed-runtime.ps1" @("-Command", "rehearse")
Assert-TokenPrintedFalse $report
Assert-True ($report.status -eq "passed") "runtime rehearsal passed"
Assert-True $report.no_worker_execution "no_worker_execution"
Assert-True $report.no_queue_apply "no_queue_apply"
Complete-Smoke "sandbox-installed-runtime-rehearsal"
