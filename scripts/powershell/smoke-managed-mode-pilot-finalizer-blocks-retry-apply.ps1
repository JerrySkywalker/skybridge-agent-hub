. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  Invoke-ManagedModePilotJson "finalizer-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr") | Out-Null
  $result = Invoke-ManagedModePilotJson "retry-apply" "low-docs" @("-StateDir", $stateDir, "-RetryAuthorization", "-RetryAuthorizationReason", "fixture duplicate prevention", "-SimulateRetryApply")
  if ($result.ok -ne $false -or @($result.blockers) -notcontains "prior_finalizer_evidence_present") { throw "Retry apply was not blocked after finalizer completion." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-blocks-retry-apply"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}

