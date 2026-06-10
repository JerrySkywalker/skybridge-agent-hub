. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $clean = Invoke-ManagedModePilotJson "finalizer-preview" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($clean.state.no_raw_artifacts -ne $true) { throw "Expected clean fixture to report no raw artifacts." }
  Write-ManagedModePilotRawArtifact -StateDir $stateDir
  $blocked = Invoke-ManagedModePilotJson "finalizer-preview" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if (@($blocked.blockers) -notcontains "raw_or_secret_artifacts_present") { throw "Raw artifact was not blocked." }
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-no-raw-artifacts"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}

