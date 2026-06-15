$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$auth = Invoke-SmokeJson "skybridge-local-auth.ps1" @("-Command", "auth-gate")
$consent = Invoke-SmokeJson "skybridge-host-consent-preview.ps1" @("-Command", "consent-gate")
$interlock = Invoke-SmokeJson "skybridge-installer-safety-interlock.ps1" @("-Command", "gate")
Assert-False $auth.execution_enabled "auth.execution_enabled"
Assert-False $consent.host_mutation_allowed "consent.host_mutation_allowed"
Assert-False $consent.auth_can_enable_host_mutation "consent.auth_can_enable_host_mutation"
Assert-False $interlock.real_install_allowed "interlock.real_install_allowed"
Assert-False $interlock.registry_write_allowed "interlock.registry_write_allowed"
Assert-False $interlock.startup_write_allowed "interlock.startup_write_allowed"
Assert-False $interlock.scheduled_task_allowed "interlock.scheduled_task_allowed"
Assert-False $interlock.service_install_allowed "interlock.service_install_allowed"
Assert-False $interlock.path_mutation_allowed "interlock.path_mutation_allowed"
Assert-False $interlock.powercfg_allowed "interlock.powercfg_allowed"
Write-Host "[smoke-installer-consent-interlock] ok"
