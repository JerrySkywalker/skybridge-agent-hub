. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
foreach ($command in @("status", "safe-summary", "completed-runs", "release-readiness", "operator-guidance", "no-execution-gate", "stale-smoke-list", "release-report")) {
  $result = Invoke-ManagedModeV0Json $command
  Assert-ManagedModeV0SafeJson $result
}
Write-ManagedModeV0SmokeResult "managed-mode-v0-token-printed-false"
