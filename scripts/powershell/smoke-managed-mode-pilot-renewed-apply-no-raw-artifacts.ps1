. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$reason = "Renewed operator authorization after prior launcher failure before execution; launcher repair merged; no prior task PR or executor evidence exists."
try {
  Write-ManagedModePilotRawArtifact -StateDir $stateDir
  $result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-StateDir", $stateDir, "-RequireRenewedAuthorization", "-RenewedAuthorization", "-RenewedAuthorizationReason", $reason, "-SimulateApply")
  if ($result.ok -ne $false -or $result.prior_attempt_state -ne "prior_attempt_unsafe_raw_artifacts") { throw "Raw prior artifact did not fail closed." }
  Assert-ManagedModeSafeJson $result
  Write-ManagedModeSmokeResult "managed-mode-pilot-renewed-apply-no-raw-artifacts"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
