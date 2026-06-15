. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "safe-summary")
Assert-False $summary.result.starts_codex_worker "starts_codex_worker"
Assert-False $summary.result.execution_enabled "execution_enabled"
Assert-TokenPrintedFalse $summary
Complete-Smoke "repo-local-launcher-no-codex-worker"
