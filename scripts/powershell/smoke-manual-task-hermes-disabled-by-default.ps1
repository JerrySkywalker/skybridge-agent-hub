$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$queue = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "list")
if ($queue.provider.provider_id -ne "mock") { throw "Default provider must be mock." }
Assert-False $queue.provider.hermes_live_call_enabled "hermes_live_call_enabled"
Assert-False $queue.provider.network_enabled "network_enabled"
Write-Host "[smoke-manual-task-hermes-disabled-by-default] ok"
