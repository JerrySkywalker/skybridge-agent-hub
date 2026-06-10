. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $state = Invoke-ManagedModePilotJson "timeout-state" "low-docs" @("-StateDir", $stateDir)
  if ($state.prior_state -ne "prior_attempt_timed_out_no_mutation") { throw "Expected timeout no-mutation classification." }
  $ready = Invoke-ManagedModePilotJson "retry-readiness" "low-docs" @("-StateDir", $stateDir)
  if ($ready.can_retry -ne $true -or $ready.remaining_retry_count -ne 1) { throw "Expected retry readiness for safe timeout." }
  Assert-ManagedModeSafeJson $ready
  Write-ManagedModeSmokeResult "managed-mode-pilot-classifies-timeout-no-mutation"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
