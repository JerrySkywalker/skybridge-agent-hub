. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-windows-launcher-preview.ps1" @("-Command", "startup-entry-preview")
Assert-False $report.registry_mutation "registry_mutation"
Assert-False $report.scheduled_task_creation "scheduled_task_creation"
Assert-False $report.service_creation "service_creation"
Complete-Smoke "windows-launcher-preview-no-registry-mutation"
