$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "report")
Assert-False $report.worker_execution_started "worker_execution_started"
if (@($report.disabled_capabilities) -notcontains "worker_execution") { throw "worker_execution not listed as disabled." }
Write-Host "[smoke-live-local-no-worker-execution] ok"
