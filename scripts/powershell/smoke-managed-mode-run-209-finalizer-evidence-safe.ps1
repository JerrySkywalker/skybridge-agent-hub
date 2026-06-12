. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$evidence = Invoke-ManagedModeRunJson "run-finalizer-evidence"
if ($evidence.no_raw_artifacts -ne $true) { throw "Expected no raw artifacts." }
if ($evidence.token_printed -ne $false) { throw "Expected token_printed=false." }
if ($evidence.final_state -notin @("ready_to_finalize", "managed_mode_run_209_completed")) { throw "Unexpected finalizer evidence state." }
Assert-ManagedModeRunSafeJson $evidence
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-evidence-safe"
