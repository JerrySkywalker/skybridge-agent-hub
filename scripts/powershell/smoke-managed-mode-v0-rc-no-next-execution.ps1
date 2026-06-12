. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$gate = Invoke-ManagedModeV0Json "no-execution-gate"
Assert-ManagedModeV0SafeJson $gate
if ($gate.no_next_execution_authorized -ne $true) { throw "Expected no next execution authorization." }
if ($gate.run_apply_enabled -ne $false -or $gate.general_bounded_queue_apply_enabled -ne $false) { throw "Execution gates must be disabled." }
Write-ManagedModeV0SmokeResult "managed-mode-v0-rc-no-next-execution"
