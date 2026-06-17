$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$oldBase = $env:HERMES_API_BASE
$oldKey = $env:HERMES_API_KEY
$oldKeyFile = $env:HERMES_API_KEY_FILE
try {
  Remove-Item Env:HERMES_API_BASE -ErrorAction SilentlyContinue
  Remove-Item Env:HERMES_API_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:HERMES_API_KEY_FILE -ErrorAction SilentlyContinue
  $summary = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "safe-summary")
  Assert-False $summary.cloud_hermes_provider_enabled "cloud_hermes_provider_enabled"
  Assert-False $summary.server_mediated_llm_inference_enabled "server_mediated_llm_inference_enabled"
  Assert-False $summary.hermes_live_call_enabled "hermes_live_call_enabled"
} finally {
  if ($null -ne $oldBase) { $env:HERMES_API_BASE = $oldBase } else { Remove-Item Env:HERMES_API_BASE -ErrorAction SilentlyContinue }
  if ($null -ne $oldKey) { $env:HERMES_API_KEY = $oldKey } else { Remove-Item Env:HERMES_API_KEY -ErrorAction SilentlyContinue }
  if ($null -ne $oldKeyFile) { $env:HERMES_API_KEY_FILE = $oldKeyFile } else { Remove-Item Env:HERMES_API_KEY_FILE -ErrorAction SilentlyContinue }
}
Write-Host "[smoke-manual-task-server-hermes-disabled-without-config] ok"
