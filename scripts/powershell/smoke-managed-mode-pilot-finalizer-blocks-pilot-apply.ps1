. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr") | Out-Null
  $result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateApply")
  if ($result.ok -ne $false -or @($result.blockers) -notcontains "managed_mode_pilot_already_completed") { throw "Pilot apply was not blocked after finalizer completion." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-blocks-pilot-apply"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}

