. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $apply = Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($apply.final_state -ne "managed_mode_pilot_completed") { throw "Finalizer apply did not complete." }
  $state = Invoke-ManagedModePilotJson "pilot-preview" "low-docs" @("-StateDir", $stateDir)
  if ($state.state.state -ne "managed_mode_pilot_completed") { throw "Pilot preview did not report completed state." }
  Assert-ManagedModeSafeJson $state
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-completed-state"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}

