. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$gate = Invoke-ManagedModeV0Json "no-execution-gate"
if ($gate.no_next_execution_authorized -ne $true) { throw "No next execution must be authorized." }
if ($gate.run_apply_enabled -ne $false -or $gate.start_all_enabled -ne $false -or $gate.start_queue_apply_enabled -ne $false -or $gate.resume_apply_enabled -ne $false) { throw "Execution controls must be disabled." }
Assert-ManagedModeV0SafeJson $gate
Write-ManagedModeV0SmokeResult "managed-mode-v0-no-next-execution-authorized"
