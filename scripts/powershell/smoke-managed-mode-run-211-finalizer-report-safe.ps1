. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$path = Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".agent/tmp/managed-mode-run-211/finalizer-report.json"
$report = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
Assert-ManagedModeRunSafeJson $report
if ($report.final_state -ne "managed_mode_run_211_completed") { throw "Expected managed_mode_run_211_completed." }
if ($report.no_auto_merge -ne $true -or $report.human_review_confirmed -ne $true) { throw "Expected safe finalizer report flags." }
if ($report.token_printed -ne $false) { throw "Expected token_printed=false." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-finalizer-report-safe"
