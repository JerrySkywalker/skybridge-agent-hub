. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $ready = Invoke-ManagedModePilotJson "retry-readiness" "low-docs" @("-StateDir", $stateDir)
  if ($ready.can_retry -ne $true -or $ready.prior_state -ne "prior_attempt_timed_out_no_mutation" -or $ready.retry_count -ne 0) { throw "Retry readiness failed." }
  Assert-ManagedModeSafeJson $ready
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-readiness"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
