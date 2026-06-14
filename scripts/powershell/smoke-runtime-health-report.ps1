. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "report")
Assert-FileExists ".agent/tmp/local-runtime/runtime-health-report.json"
Assert-FileExists ".agent/tmp/local-runtime/runtime-plan.json"
Assert-False $report.health.process_health.raw_process_output_persisted "raw_process_output_persisted"
Assert-False $report.health.process_health.environment_variables_persisted "environment_variables_persisted"
Complete-Smoke "runtime-health-report"
