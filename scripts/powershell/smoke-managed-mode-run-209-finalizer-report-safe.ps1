. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$report = Invoke-ManagedModeRunJson "run-finalizer-report"
if ($report.no_raw_artifacts -ne $true) { throw "Expected no raw artifacts in report." }
if ($report.token_printed -ne $false) { throw "Expected token_printed=false." }
Assert-ManagedModeRunSafeJson $report
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-report-safe"
