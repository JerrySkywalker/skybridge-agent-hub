. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$readiness = Invoke-ManagedModeV0Json "release-readiness"
if ($readiness.general_bounded_queue_apply_enabled -ne $false) { throw "General bounded queue apply must be disabled." }
if ($readiness.multi_workunit_queue_enabled -ne $false) { throw "Multi-workunit apply must be disabled." }
Assert-ManagedModeV0SafeJson $readiness
Write-ManagedModeV0SmokeResult "managed-mode-v0-9-bounded-queue-disabled"
