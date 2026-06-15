. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-recovery-sandbox.ps1" @("-Command", "recovery-plan")
Assert-TokenPrintedFalse $plan
Assert-True $plan.cleanup_preview_only "cleanup_preview_only"
Assert-False $plan.process_kill_allowed "process_kill_allowed"
Complete-Smoke "orphan-lock-cleanup-hardening"
