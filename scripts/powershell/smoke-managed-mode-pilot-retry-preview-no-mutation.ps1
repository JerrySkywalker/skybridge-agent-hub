. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotTimeoutResult -StateDir $stateDir
  $before = (Get-ChildItem -LiteralPath $stateDir -File | Select-Object -ExpandProperty Name) -join ","
  $preview = Invoke-ManagedModePilotJson "retry-preview" "low-docs" @("-StateDir", $stateDir)
  $after = (Get-ChildItem -LiteralPath $stateDir -File | Select-Object -ExpandProperty Name) -join ","
  if ($preview.no_mutation -ne $true -or $before -ne $after) { throw "Retry preview mutated state." }
  if ($preview.retry_target_path -ne "docs/managed-mode-pilot-orientation.md") { throw "Retry target path mismatch." }
  Assert-ManagedModeSafeJson $preview
  Write-ManagedModeSmokeResult "managed-mode-pilot-retry-preview-no-mutation"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
