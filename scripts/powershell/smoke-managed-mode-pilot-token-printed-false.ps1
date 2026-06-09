. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
foreach ($command in @("pilot-preview", "apply-gate", "pilot-apply")) {
  Invoke-ManagedModePilotJson $command "low-docs" @("-SimulateApply") | Out-Null
}
Write-ManagedModeSmokeResult "managed-mode-pilot-token-printed-false"
