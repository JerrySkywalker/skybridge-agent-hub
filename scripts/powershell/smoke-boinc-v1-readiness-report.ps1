. "$PSScriptRoot/smoke-boinc-v1-common.ps1"
$readiness = Invoke-BoincV1PreviewJson -Command "readiness"
@("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211") | ForEach-Object {
  Assert-True ($readiness.completed_managed_mode_runs -contains $_) "Missing completed run $_."
}
Assert-Equal $readiness.scheduler_preview.selected_workunit_count 2 "Scheduler preview must select two workunits."
Assert-True ([bool]$readiness.apply_disabled) "Readiness must keep apply disabled."
Assert-True ([bool]$readiness.no_next_execution_authorized) "Readiness must keep no_next_execution_authorized=true."
@("reliable two-workunit finalizer", "desktop resident enforcement", "failure budget policy", "queue drain implementation", "operator approval flow", "release/audit docs", "long-run evidence retention model", "explicit v1 authorization goal") | ForEach-Object {
  Assert-True ($readiness.readiness_gaps_before_v1_apply -contains $_) "Missing readiness gap $_."
}
Write-SmokeResult "boinc-v1-readiness-report"
