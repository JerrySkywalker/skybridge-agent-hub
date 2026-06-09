. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  foreach ($command in @("finalizer-preview", "finalizer-evidence", "finalizer-report", "finalizer-apply")) {
    $result = Invoke-ManagedModePilotJson $command "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
    Assert-ManagedModeSafeJson $result
  }
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-token-printed-false"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
