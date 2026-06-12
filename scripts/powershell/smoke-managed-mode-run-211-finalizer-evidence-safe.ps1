. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$path = Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".agent/tmp/managed-mode-run-211/finalizer-evidence.json"
$evidence = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
Assert-ManagedModeRunSafeJson $evidence
if ($evidence.final_state -ne "managed_mode_run_211_completed") { throw "Expected managed_mode_run_211_completed." }
if ($evidence.resource_gate_pass -ne $true) { throw "Expected resource_gate_pass=true." }
if ($evidence.no_second_run -ne $true -or $evidence.no_auto_merge -ne $true -or $evidence.human_review_confirmed -ne $true) { throw "Expected safe finalizer flags." }
if (-not $evidence.evidence_hashes.run_result_sha256 -or -not $evidence.evidence_hashes.run_evidence_sha256) { throw "Expected evidence hashes." }
if ($evidence.token_printed -ne $false) { throw "Expected token_printed=false." }
Write-ManagedModeRunSmokeResult "managed-mode-run-211-finalizer-evidence-safe"
