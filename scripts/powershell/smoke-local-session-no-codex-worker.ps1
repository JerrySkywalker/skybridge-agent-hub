. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "safe-summary")
Assert-False $summary.starts_codex_worker "starts_codex_worker"
Assert-False $summary.execution_enabled "execution_enabled"
Assert-TokenPrintedFalse $summary
Complete-Smoke "local-session-no-codex-worker"
