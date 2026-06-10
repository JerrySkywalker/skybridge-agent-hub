. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotRetryResult -StateDir $stateDir -TimedOut:$false
  $preview = Invoke-ManagedModePilotJson "replacement-retry-preview" "low-docs" @("-StateDir", $stateDir)
  if ($preview.no_mutation -ne $true) { throw "Replacement retry preview must be non-mutating." }
  if ($preview.target_path -ne "docs/managed-mode-pilot-orientation.md") { throw "Unexpected replacement retry target path." }
  if ($preview.readiness.selected_invocation_profile -ne "profile_workspace_write_workdir") { throw "Preview must use repaired workspace-write profile." }
  Assert-ManagedModeSafeJson $preview
  Write-ManagedModeSmokeResult "managed-mode-replacement-retry-preview-no-mutation"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
