$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$providers = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "provider-list")
if ($providers.default_provider_id -ne "mock") { throw "Default provider must be mock." }
$mock = @($providers.providers | Where-Object { $_.provider_id -eq "mock" })[0]
$hermes = @($providers.providers | Where-Object { $_.provider_id -eq "hermes_deepseek" })[0]
if ($null -eq $mock -or $null -eq $hermes) { throw "Expected mock and hermes_deepseek providers." }
Assert-False $mock.hermes_live_call_enabled "mock.hermes_live_call_enabled"
Assert-False $mock.network_enabled "mock.network_enabled"
Assert-False $hermes.hermes_live_call_enabled "hermes.hermes_live_call_enabled"
Assert-Truthy $providers.live_call_disabled_by_default "live_call_disabled_by_default"
Write-Host "[smoke-manual-task-provider-mock-default] ok"
