$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

if ([string]::IsNullOrWhiteSpace($env:HERMES_API_BASE) -or ([string]::IsNullOrWhiteSpace($env:HERMES_API_KEY) -and [string]::IsNullOrWhiteSpace($env:HERMES_API_KEY_FILE))) {
  [pscustomobject]@{
    schema = "skybridge.manual_task_result.v1"
    status = "skipped"
    provider_id = "skybridge_server_hermes"
    reason = "server_side_hermes_config_missing"
    live_call_performed = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 10
  Write-Host "[smoke-manual-task-server-hermes-live-optin] skipped missing server-side config"
  exit 0
}

Remove-Item -LiteralPath (Join-Path (Resolve-Path "$PSScriptRoot\..\..") ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-ProviderId", "skybridge_server_hermes", "-Question", "Answer safely without realtime claims.") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "run-next-skybridge-hermes")
if ($result.provider_id -ne "skybridge_server_hermes") { throw "Expected skybridge_server_hermes provider." }
Assert-False $result.output_executed "output_executed"
Write-Host "[smoke-manual-task-server-hermes-live-optin] ok"
