. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-local-launch.ps1" @("-Command", "report")
Assert-True $report.preview_only "preview_only"
foreach ($plan in $report.plans) {
  Assert-True $plan.dry_run "dry_run"
  Assert-False $plan.execution_enabled "execution_enabled"
  Assert-False $plan.queue_apply_enabled "queue_apply_enabled"
}
Complete-Smoke "local-launch-preview"
