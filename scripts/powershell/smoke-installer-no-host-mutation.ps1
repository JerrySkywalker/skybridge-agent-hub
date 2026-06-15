. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-installer-candidate.ps1" @("-Command", "safe-summary")
Assert-TokenPrintedFalse $summary
Assert-False $summary.host_mutation_allowed "host_mutation_allowed"
Assert-False $summary.registry_write_allowed "registry_write_allowed"
Assert-False $summary.startup_write_allowed "startup_write_allowed"
Assert-False $summary.scheduled_task_allowed "scheduled_task_allowed"
Assert-False $summary.service_install_allowed "service_install_allowed"
Assert-False $summary.powercfg_allowed "powercfg_allowed"
Complete-Smoke "installer-no-host-mutation"
