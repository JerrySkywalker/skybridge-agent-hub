. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "start-preview")
Assert-True $plan.dry_run "dry_run"
Assert-True $plan.preview_only "preview_only"
Assert-False $plan.execution_enabled "execution_enabled"
Assert-False $plan.queue_apply_enabled "queue_apply_enabled"
Complete-Smoke "local-runtime-start-preview"
