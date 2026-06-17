$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
Remove-Item -LiteralPath (Join-Path $root ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-Question", "Summarize the local manual queue boundary.") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "run-next-mock")
if ($result.schema -ne "skybridge.manual_task_result.v1") { throw "Manual task result schema mismatch." }
if ($result.provider.provider_id -ne "mock") { throw "Expected mock provider." }
if ($result.status -ne "succeeded") { throw "Mock provider did not succeed." }
if ($result.result_preview -notlike "Mock reply*") { throw "Missing deterministic mock preview." }
Assert-False $result.provider.network_enabled "network_enabled"
Assert-False $result.provider.hermes_live_call_enabled "hermes_live_call_enabled"
Assert-False $result.output_executed "output_executed"
Write-Host "[smoke-manual-task-run-next-mock] ok"
