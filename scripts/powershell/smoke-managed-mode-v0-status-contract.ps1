. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$status = Invoke-ManagedModeV0Json "status"
if ($status.schema -ne "skybridge.managed_mode_v0_status.v1") { throw "Unexpected v0 status schema." }
if ($status.completed_runs.schema -ne "skybridge.managed_mode_v0_completed_runs.v1") { throw "Missing completed-runs contract." }
if ($status.release_readiness.schema -ne "skybridge.managed_mode_v0_release_readiness.v1") { throw "Missing release readiness contract." }
if ($status.operator_guidance.schema -ne "skybridge.managed_mode_v0_operator_guidance.v1") { throw "Missing operator guidance contract." }
Assert-ManagedModeV0SafeJson $status
Write-ManagedModeV0SmokeResult "managed-mode-v0-status-contract"
