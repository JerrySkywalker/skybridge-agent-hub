. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $state = Invoke-ManagedModePilotJson "timeout-state" "low-docs" @("-StateDir", $stateDir)
  if ($state.schema -ne "skybridge.managed_mode_pilot_timeout_state.v1") { throw "Timeout state schema mismatch." }
  if ($state.diagnostics.token_printed -ne $false -or $state.token_printed -ne $false) { throw "Expected token_printed=false." }
  if ($state.diagnostics.changed_file_count -ne 0 -or $state.diagnostics.open_pr_count -ne 0) { throw "Expected no mutation diagnostics." }
  Assert-ManagedModeSafeJson $state
  Write-ManagedModeSmokeResult "managed-mode-pilot-timeout-state-contract"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
