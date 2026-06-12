. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$readiness = Invoke-ManagedModeV0Json "release-readiness"
Assert-ManagedModeV0SafeJson $readiness
if ($readiness.resource_gate_required_for_next_run -ne $true) { throw "Expected resource gate requirement." }
if ($readiness.active_tasks -ne 0 -or $readiness.stale_leases -ne 0 -or $readiness.runner_lock -ne "none") { throw "Expected clear local gate state." }
Write-ManagedModeV0SmokeResult "managed-mode-v0-rc-resource-gate-present"
