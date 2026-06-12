. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$gate = Invoke-ManagedModeV0Json "no-execution-gate"
if ($gate.no_next_execution_authorized -ne $true) { throw "Expected no next execution authorized." }
if ($gate.run_apply_enabled -ne $false -or $gate.start_all_enabled -ne $false -or $gate.start_queue_apply_enabled -ne $false -or $gate.resume_apply_enabled -ne $false) { throw "Expected execution controls disabled." }
if ($gate.readiness.next_safe_action -ne "plan two-workunit preview only") { throw "Expected two-workunit preview next action." }
Assert-ManagedModeV0SafeJson $gate
Write-ManagedModeV0SmokeResult "managed-mode-v0-9-no-next-execution"
