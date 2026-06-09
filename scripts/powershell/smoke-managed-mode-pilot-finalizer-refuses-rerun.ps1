. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $first = Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($first.ok -ne $true) { throw "Initial finalizer fixture apply failed." }
  $second = Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($second.ok -ne $false -or @($second.blockers) -notcontains "managed_mode_pilot_already_completed") { throw "Finalizer rerun was not refused." }
  Assert-ManagedModeSafeJson $second
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-refuses-rerun"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
