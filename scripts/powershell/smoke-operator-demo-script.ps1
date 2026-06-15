. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-operator-demo-script.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $report
Assert-True $report.no_worker_execution "no_worker_execution"
Assert-True $report.no_host_mutation "no_host_mutation"
Complete-Smoke "operator-demo-script"
