$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$providers = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "provider-list")
if ($providers.default_provider_id -ne "mock") { throw "Default provider must remain mock." }
$serverProvider = @($providers.providers | Where-Object { $_.provider_id -eq "skybridge_server_hermes" })[0]
$localDirect = @($providers.providers | Where-Object { $_.provider_id -eq "hermes_deepseek" })[0]
if ($null -eq $serverProvider) { throw "Missing skybridge_server_hermes provider." }
if ($null -eq $localDirect) { throw "Missing deprecated hermes_deepseek provider." }
Assert-False $serverProvider.hermes_live_call_enabled "serverProvider.hermes_live_call_enabled"
Assert-False $serverProvider.remote_llm_inference_enabled "serverProvider.remote_llm_inference_enabled"
Assert-Truthy $localDirect.deprecated "hermes_deepseek.deprecated"
Assert-Truthy $localDirect.preview_only "hermes_deepseek.preview_only"
Assert-False $providers.client_secret_required "client_secret_required"
Write-Host "[smoke-manual-task-server-hermes-provider-contract] ok"
