. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$reason = "Renewed operator authorization after prior launcher failure before execution; launcher repair merged; no prior task PR or executor evidence exists."
try {
  $allowed = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-StateDir", $stateDir, "-RequireRenewedAuthorization", "-RenewedAuthorization", "-RenewedAuthorizationReason", $reason, "-SimulateApply")
  if ($allowed.ok -ne $true -or $allowed.codex_execution_count -ne 1 -or $allowed.pr_count -ne 1) { throw "Renewed apply did not stay one-shot." }
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $blocked = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-StateDir", $stateDir, "-RequireRenewedAuthorization", "-RenewedAuthorization", "-RenewedAuthorizationReason", $reason, "-SimulateApply")
  if ($blocked.ok -ne $false -or @($blocked.blockers) -notcontains "prior_attempt_already_produced_task_pr_or_evidence") { throw "Renewed apply did not refuse a second attempt after evidence." }
  Assert-ManagedModeSafeJson $allowed
  Assert-ManagedModeSafeJson $blocked
  Write-ManagedModeSmokeResult "managed-mode-pilot-renewed-apply-one-shot-only"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
