. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotRetryResult -StateDir $stateDir -TimedOut:$false
  $ready = Invoke-ManagedModePilotJson "replacement-retry-readiness" "low-docs" @("-StateDir", $stateDir)
  if ($ready.previous_retry_classification -ne "invocation_failed_no_mutation") { throw "Expected invocation_failed_no_mutation readiness input." }
  if ($ready.selected_invocation_profile -ne "profile_workspace_write_workdir") { throw "Expected repaired workspace-write profile." }
  if ($ready.replacement_retry_count -ne 0 -or $ready.max_replacement_retries -ne 1) { throw "Unexpected replacement retry budget." }
  if (@($ready.blockers | Where-Object { $_ -eq "workspace_write_profile_not_selected" }).Count -ne 0) { throw "Invocation repair blocker should not be present." }
  Assert-ManagedModeSafeJson $ready
  Write-ManagedModeSmokeResult "managed-mode-replacement-retry-readiness"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
