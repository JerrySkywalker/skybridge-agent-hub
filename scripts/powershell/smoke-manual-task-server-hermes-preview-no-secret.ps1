$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

Remove-Item -LiteralPath (Join-Path (Resolve-Path "$PSScriptRoot\..\..") ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-ProviderId", "hermes_deepseek", "-Question", "What should the operator inspect before Hermes?") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "run-next-hermes-preview")
if ($result.provider_id -ne "hermes_deepseek") { throw "Expected hermes_deepseek preview provider." }
if ($result.provider_status -ne "preview_no_network") { throw "Expected preview no-network status." }
if ($result.result_preview -notlike "*deprecated local-direct provider*") { throw "Expected deprecated local-direct preview marker." }
Assert-False $result.live_call_performed "live_call_performed"
Assert-False $result.output_executed "output_executed"
Write-Host "[smoke-manual-task-server-hermes-preview-no-secret] ok"
