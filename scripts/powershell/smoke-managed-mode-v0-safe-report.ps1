. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$report = Invoke-ManagedModeV0Json "release-report"
if ($report.schema -ne "skybridge.managed_mode_v0_release_report.v1") { throw "Unexpected release report schema." }
if (-not $report.report_path) { throw "Release report path missing." }
if ($report.status.release_readiness.no_next_execution_authorized -ne $true) { throw "Report must preserve no-next-execution boundary." }
Assert-ManagedModeV0SafeJson $report
Write-ManagedModeV0SmokeResult "managed-mode-v0-safe-report"
