. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$evidence = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".agent/tmp/managed-mode-run-210/finalizer-evidence.json") | ConvertFrom-Json
Assert-ManagedModeRunSafeJson $evidence
if ($evidence.final_state -ne "managed_mode_run_210_completed") { throw "Expected managed_mode_run_210_completed." }
if ($evidence.no_raw_artifacts -ne $true -or $evidence.token_printed -ne $false) { throw "Expected safe finalizer evidence." }
Write-ManagedModeRunSmokeResult "managed-mode-run-210-finalizer-evidence-safe"
