$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
$configPath = Join-Path $root ".agent\local\hermes-deepseek.local.json"
if (-not (Test-Path -LiteralPath $configPath)) {
  [pscustomobject]@{ ok = $true; skipped = $true; reason = "local_config_missing"; token_printed = $false } | ConvertTo-Json -Compress
  return
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.live_enabled -ne $true) {
  [pscustomobject]@{ ok = $true; skipped = $true; reason = "live_enabled_false"; token_printed = $false } | ConvertTo-Json -Compress
  return
}

Remove-Item -LiteralPath (Join-Path $root ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-ProviderId", "hermes_deepseek", "-Question", "Answer safely without realtime claims.") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "run-next-hermes-live-optin", "-AllowLive")
if ($result.provider_id -ne "hermes_deepseek") { throw "Expected hermes_deepseek provider." }
if ($env:CI -eq "true" -or $env:GITHUB_ACTIONS -eq "true" -or $env:SKYBRIDGE_CI -eq "true") {
  if ($result.status -ne "blocked") { throw "CI must block Hermes live opt-in." }
  Assert-False $result.live_call_performed "live_call_performed"
} else {
  if ($result.status -notin @("succeeded", "failed")) { throw "Unexpected live opt-in status." }
  Assert-Truthy $result.live_call_performed "live_call_performed"
  Assert-Truthy $result.remote_llm_inference_enabled "remote_llm_inference_enabled"
}
Assert-False $result.output_executed "output_executed"
Assert-False $result.command_executed "command_executed"
Write-Host "[smoke-manual-task-hermes-live-optin] ok"
