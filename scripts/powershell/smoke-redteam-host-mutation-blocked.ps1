$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$hostReport = Invoke-SmokeJson "skybridge-host-consent-preview.ps1" @("-Command", "report")
Assert-False $hostReport.consent_gate.host_mutation_allowed "host_mutation_allowed"
Assert-False $hostReport.consent_gate.auth_can_enable_host_mutation "auth_can_enable_host_mutation"
Assert-False $hostReport.host_mutation_performed "host_mutation_performed"
Assert-False $hostReport.installer_real_mutation_allowed "installer_real_mutation_allowed"

$interlock = Invoke-SmokeJson "skybridge-installer-safety-interlock.ps1" @("-Command", "report")
Assert-False $interlock.real_install_allowed "real_install_allowed"
Assert-False $interlock.registry_write_allowed "registry_write_allowed"
Assert-False $interlock.startup_write_allowed "startup_write_allowed"
Assert-False $interlock.scheduled_task_allowed "scheduled_task_allowed"
Assert-False $interlock.service_install_allowed "service_install_allowed"
Assert-False $interlock.path_mutation_allowed "path_mutation_allowed"
Assert-False $interlock.powercfg_allowed "powercfg_allowed"

Write-Host "[smoke-redteam-host-mutation-blocked] ok"
