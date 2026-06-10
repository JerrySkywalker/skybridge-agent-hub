. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $apply = Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($apply.ok -ne $true) { throw "Finalizer fixture apply failed." }
  $report = Get-Content -Raw -LiteralPath (Join-Path $stateDir "finalizer-report.json") | ConvertFrom-Json
  if ($report.final_state -ne "managed_mode_pilot_completed") { throw "Unexpected finalizer report state." }
  if ($report.next_safe_action -ne "plan next managed-mode repeatability goal") { throw "Finalizer report next action mismatch." }
  Assert-ManagedModeSafeJson $report
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-report-safe"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}

