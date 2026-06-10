. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$reason = "Operator-authorized one-time retry after prior Codex timeout without mutation; timeout recovery policy merged; prompt narrowed; no prior PR or executor evidence exists."
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $result = Invoke-ManagedModePilotJson "retry-apply" "low-docs" @("-StateDir", $stateDir, "-RetryAuthorization", "-RetryAuthorizationReason", $reason, "-SimulateRetryApply", "-SimulateRetryOutcome", "timeout")
  if ($result.final_state -ne "pilot_failed_timeout_retry_exhausted" -or $result.timed_out -ne $true) { throw "Retry timeout did not exhaust budget." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-timeout-exhausts-budget"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
