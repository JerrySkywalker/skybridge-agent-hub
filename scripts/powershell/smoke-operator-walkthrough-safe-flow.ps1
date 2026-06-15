. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-operator-walkthrough.ps1" @("-Command", "report")
if ($report.schema -ne "skybridge.operator_walkthrough_report.v1") { throw "schema mismatch" }
Assert-True $report.no_worker_execution "no_worker_execution"
Assert-True $report.no_workunit_apply "no_workunit_apply"
Assert-True $report.no_queue_apply "no_queue_apply"
Assert-False $report.raw_logs_persisted "raw_logs_persisted"
Assert-TokenPrintedFalse $report
Complete-Smoke "operator-walkthrough-safe-flow"
