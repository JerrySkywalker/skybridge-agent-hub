. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $preview = Invoke-ManagedModePilotJson "finalizer-preview" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($preview.ok -ne $true -or $preview.state.no_second_workunit -ne $true -or $preview.state.workunits_executed -ne 1) { throw "Finalizer did not verify one workunit." }
  $blocked = Invoke-ManagedModePilotJson "finalizer-preview" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr", "-SimulateFinalizerSecondWorkunit")
  if (@($blocked.blockers) -notcontains "expected_exactly_one_pilot_workunit") { throw "Finalizer did not block second workunit evidence." }
  Assert-ManagedModeSafeJson $preview
  Assert-ManagedModeSafeJson $blocked
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-no-second-workunit"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
