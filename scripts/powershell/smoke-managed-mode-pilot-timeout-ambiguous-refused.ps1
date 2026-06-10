. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotAmbiguousResult -StateDir $stateDir
  $ready = Invoke-ManagedModePilotJson "retry-readiness" "low-docs" @("-StateDir", $stateDir)
  if ($ready.can_retry -ne $false -or $ready.prior_state -ne "prior_attempt_ambiguous") { throw "Expected ambiguous state to refuse retry." }
  Assert-ManagedModeSafeJson $ready
  Write-ManagedModeSmokeResult "managed-mode-pilot-timeout-ambiguous-refused"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
