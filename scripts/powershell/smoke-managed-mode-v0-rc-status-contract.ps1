. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$status = Invoke-ManagedModeV0Json "status"
Assert-ManagedModeV0SafeJson $status
if ($status.schema -ne "skybridge.managed_mode_v0_status.v1") { throw "Unexpected status schema." }
if ($status.release_readiness.release_ready -ne $true) { throw "Expected RC ready." }
if ($status.operator_guidance.current_state -ne "managed_mode_v0_release_candidate_ready") { throw "Expected RC-ready guidance." }
Write-ManagedModeV0SmokeResult "managed-mode-v0-rc-status-contract"
