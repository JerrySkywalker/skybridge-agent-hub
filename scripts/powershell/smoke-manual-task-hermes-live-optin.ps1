$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
Remove-Item -LiteralPath (Join-Path $root ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-ProviderId", "hermes_deepseek", "-Question", "Answer safely without realtime claims.") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "run-next-hermes-live-optin", "-AllowLive")
if ($result.provider_id -ne "hermes_deepseek") { throw "Expected hermes_deepseek provider." }
if ($result.status -ne "blocked") { throw "Deprecated local-direct Hermes live opt-in must be blocked." }
if ($result.provider_status -ne "deprecated_local_direct_live_blocked") { throw "Expected deprecated local-direct blocked status." }
Assert-False $result.live_call_performed "live_call_performed"
Assert-False $result.remote_llm_inference_enabled "remote_llm_inference_enabled"
Assert-False $result.output_executed "output_executed"
Assert-False $result.command_executed "command_executed"
Write-Host "[smoke-manual-task-hermes-live-optin] ok"
