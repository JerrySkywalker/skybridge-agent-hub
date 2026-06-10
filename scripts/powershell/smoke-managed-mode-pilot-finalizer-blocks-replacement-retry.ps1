. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  Write-ManagedModePilotRetryResult -StateDir $stateDir -TimedOut:$false
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr") | Out-Null
  $result = Invoke-ManagedModePilotJson "replacement-retry-apply" "low-docs" @("-StateDir", $stateDir, "-ReplacementRetryAuthorization", "-ReplacementRetryAuthorizationReason", "fixture duplicate prevention", "-SimulateReplacementRetryApply")
  if ($result.ok -ne $false -or @($result.blockers) -notcontains "prior_finalizer_evidence_present") { throw "Replacement retry apply was not blocked after finalizer completion." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-blocks-replacement-retry"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}

