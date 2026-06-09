. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $apply = Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($apply.ok -ne $true -or $apply.final_state -ne "managed_mode_pilot_completed") { throw "Finalizer fixture apply did not complete." }
  $evidencePath = Join-Path $stateDir "finalizer-evidence.json"
  $reportPath = Join-Path $stateDir "finalizer-report.json"
  if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf) -or -not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Finalizer evidence/report missing." }
  $evidence = Get-Content -Raw -LiteralPath $evidencePath | ConvertFrom-Json
  if ($evidence.final_state -ne "managed_mode_pilot_completed" -or $evidence.no_raw_artifacts -ne $true) { throw "Unsafe finalizer evidence." }
  Assert-ManagedModeSafeJson $apply
  Assert-ManagedModeSafeJson $evidence
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-evidence-safe"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
