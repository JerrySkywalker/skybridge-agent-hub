. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $ready = Invoke-ManagedModePilotJson "retry-readiness" "low-docs" @("-StateDir", $stateDir)
  if ($ready.policy.max_retries -ne 1 -or $ready.policy.retry_reason_required -ne $true) { throw "Retry policy contract mismatch." }
  if ($ready.policy.retry_allowed_only_after_timeout_no_mutation -ne $true -or $ready.policy.retry_disallowed_after_pr -ne $true) { throw "Retry policy gates missing." }
  Assert-ManagedModeSafeJson $ready
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-policy-contract"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
