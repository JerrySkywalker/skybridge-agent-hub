. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "safe-summary")
Assert-False $summary.result.queue_apply_enabled "queue_apply_enabled"
Assert-TokenPrintedFalse $summary
Complete-Smoke "repo-local-launcher-no-queue-apply"
