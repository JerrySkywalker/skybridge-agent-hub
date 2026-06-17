$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "report")
Assert-False $report.summary.workunit_created "workunit_created"
if ($report.queue.PSObject.Properties["workunit_id"]) { throw "Manual task queue must not expose workunit_id." }
Write-Host "[smoke-manual-task-no-workunit-created] ok"
