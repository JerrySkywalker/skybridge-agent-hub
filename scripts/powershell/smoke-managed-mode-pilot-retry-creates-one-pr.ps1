. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$reason = "Operator-authorized one-time retry after prior Codex timeout without mutation; timeout recovery policy merged; prompt narrowed; no prior PR or executor evidence exists."
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $result = Invoke-ManagedModePilotJson "retry-apply" "low-docs" @("-StateDir", $stateDir, "-RetryAuthorization", "-RetryAuthorizationReason", $reason, "-SimulateRetryApply", "-SimulateRetryOutcome", "success")
  if ($result.pr_created -ne $true -or $result.pr_count -ne 1) { throw "Retry simulation did not create one PR." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-creates-one-pr"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
