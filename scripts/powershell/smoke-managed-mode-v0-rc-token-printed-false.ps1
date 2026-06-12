. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

foreach ($command in @("status", "safe-summary", "completed-runs", "release-readiness", "release-report", "operator-guidance", "no-execution-gate", "stale-smoke-list")) {
  $value = Invoke-ManagedModeV0Json $command
  Assert-ManagedModeV0SafeJson $value
}
Write-ManagedModeV0SmokeResult "managed-mode-v0-rc-token-printed-false"
