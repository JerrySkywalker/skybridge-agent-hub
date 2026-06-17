$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
Remove-Item -LiteralPath (Join-Path $root ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-ProviderId", "hermes_deepseek", "-Question", "What should the operator check before enabling Hermes?") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "run-next-hermes-preview")
if ($result.provider_id -ne "hermes_deepseek") { throw "Expected hermes_deepseek provider." }
if ($result.provider_status -ne "preview_no_network") { throw "Expected preview_no_network provider status." }
if ($result.status -ne "succeeded") { throw "Hermes preview did not succeed." }
if ($result.result_preview -notlike "Hermes DeepSeek preview*") { throw "Missing Hermes preview result." }
Assert-False $result.live_call_performed "live_call_performed"
Assert-False $result.remote_llm_inference_enabled "remote_llm_inference_enabled"
Assert-False $result.raw_request_persisted "raw_request_persisted"
Assert-False $result.raw_response_persisted "raw_response_persisted"
Assert-False $result.output_executed "output_executed"
Write-Host "[smoke-manual-task-hermes-preview-no-network] ok"
