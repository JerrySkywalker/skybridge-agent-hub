$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$status = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "status")
if ($status.default_provider_id -ne "mock") { throw "Default provider must be mock." }
Assert-Truthy $status.hermes_disabled_by_default "hermes_disabled_by_default"
Assert-Truthy $status.no_hermes_live_call_in_ci "no_hermes_live_call_in_ci"
Assert-False $status.raw_request_persisted "raw_request_persisted"
Assert-False $status.raw_response_persisted "raw_response_persisted"
Assert-False $status.output_executed "output_executed"
Assert-False $status.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-manual-task-hermes-disabled-by-default] ok"
