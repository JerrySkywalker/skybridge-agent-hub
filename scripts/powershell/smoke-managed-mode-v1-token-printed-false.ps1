. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
foreach ($command in @("schema", "readiness", "plan-preview", "apply-gate", "pilot-preview", "evidence", "safe-summary")) {
  Invoke-ManagedModePilotJson $command | Out-Null
}
Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-SimulateApply") | Out-Null
Write-ManagedModeSmokeResult "managed-mode-v1-token-printed-false"
