. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "safe-summary")
Assert-False $summary.queue_apply_enabled "queue_apply_enabled"
Assert-TokenPrintedFalse $summary
Complete-Smoke "local-session-no-queue-apply"
