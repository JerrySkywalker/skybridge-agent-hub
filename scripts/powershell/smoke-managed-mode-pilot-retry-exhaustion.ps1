. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  Write-ManagedModePilotRetryResult -StateDir $stateDir
  $ready = Invoke-ManagedModePilotJson "retry-readiness" "low-docs" @("-StateDir", $stateDir)
  if ($ready.can_retry -ne $false -or $ready.prior_state -ne "retry_exhausted" -or $ready.remaining_retry_count -ne 0) { throw "Retry exhaustion failed." }
  Assert-ManagedModeSafeJson $ready
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-exhaustion"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
