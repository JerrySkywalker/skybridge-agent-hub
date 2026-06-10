. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$reason = "Operator-authorized one-time retry after prior Codex timeout without mutation; timeout recovery policy merged; prompt narrowed; no prior PR or executor evidence exists."
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $result = Invoke-ManagedModePilotJson "retry-apply" "low-docs" @("-StateDir", $stateDir, "-RetryAuthorization", "-RetryAuthorizationReason", $reason, "-SimulateRetryApply")
  if ($result.retry_attempt -ne 1 -or $result.codex_execution_count -ne 1 -or $result.max_retries -ne 1) { throw "Retry apply was not one-shot." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-apply-one-shot"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
