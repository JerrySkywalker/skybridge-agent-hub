$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "report")
if (@($report.disabled_capabilities) -notcontains "queue_apply") { throw "queue_apply not listed as disabled." }
$serverReport = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path "$PSScriptRoot\..\..") ".agent\tmp\live-local\live-local-server-report.json") | ConvertFrom-Json
Assert-False $serverReport.queue_apply_enabled "queue_apply_enabled"
Assert-False $serverReport.workunit_apply_enabled "workunit_apply_enabled"
Assert-False $serverReport.task_claim_enabled "task_claim_enabled"
Write-Host "[smoke-live-local-no-queue-apply] ok"
