. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-stop-hook-diagnostics.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $report
Assert-False $report.raw_hook_logs_read "raw_hook_logs_read"
Assert-False $report.raw_logs_persisted "raw_logs_persisted"
Assert-NoUnsafeText (Get-Content -Raw (Join-Path $RepoRoot ".agent/tmp/local-launcher/stop-hook-diagnostics.json"))
Complete-Smoke "stop-hook-diagnostics-no-raw-logs"
