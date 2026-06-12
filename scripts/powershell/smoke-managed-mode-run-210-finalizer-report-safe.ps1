. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$report = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".agent/tmp/managed-mode-run-210/finalizer-report.json") | ConvertFrom-Json
Assert-ManagedModeRunSafeJson $report
if ($report.final_state -ne "managed_mode_run_210_completed") { throw "Expected managed_mode_run_210_completed report." }
if ($report.evidence_path -ne ".agent/tmp/managed-mode-run-210/finalizer-evidence.json") { throw "Unexpected evidence path." }
Write-ManagedModeRunSmokeResult "managed-mode-run-210-finalizer-report-safe"
