. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$reason = "Renewed operator authorization after prior launcher failure before execution; launcher repair merged; no prior task PR or executor evidence exists."
try {
  $blocked = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-StateDir", $stateDir, "-RequireRenewedAuthorization", "-SimulateApply")
  if ($blocked.ok -ne $false -or @($blocked.blockers) -notcontains "renewed_authorization_required") { throw "Renewed apply did not require explicit authorization." }
  $allowed = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-StateDir", $stateDir, "-RequireRenewedAuthorization", "-RenewedAuthorization", "-RenewedAuthorizationReason", $reason, "-SimulateApply")
  if ($allowed.ok -ne $true -or $allowed.renewed_authorization -ne $true -or $allowed.prior_attempt_state -ne "prior_attempt_failed_before_execution") { throw "Renewed authorization contract failed." }
  Assert-ManagedModeSafeJson $blocked
  Assert-ManagedModeSafeJson $allowed
  Write-ManagedModeSmokeResult "managed-mode-pilot-renewed-authorization-contract"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
