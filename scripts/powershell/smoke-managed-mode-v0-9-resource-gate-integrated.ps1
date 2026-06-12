. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$readiness = Invoke-ManagedModeV0Json "release-readiness"
if ($readiness.resource_gate_integrated -ne $true) { throw "Expected resource gate integrated." }
if ($readiness.resource_gate_required_for_next_run -ne $true) { throw "Expected resource gate required." }
Assert-ManagedModeV0SafeJson $readiness
Write-ManagedModeV0SmokeResult "managed-mode-v0-9-resource-gate-integrated"
