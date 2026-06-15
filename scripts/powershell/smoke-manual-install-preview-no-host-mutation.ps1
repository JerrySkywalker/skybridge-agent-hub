. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-manual-install-preview.ps1" @("-Command", "plan")
Assert-TokenPrintedFalse $plan
foreach ($field in @("registry_write", "startup_write", "scheduled_task_write", "service_write", "powercfg_write", "host_mutation_allowed")) {
  Assert-False $plan.$field $field
}
Complete-Smoke "manual-install-preview-no-host-mutation"
