. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$preview = Invoke-ManagedModeRunJson "run-finalizer-preview"
if ($preview.final_state -notin @("held_waiting_human_pr_review", "finalizer_blocked", "ready_to_finalize", "managed_mode_run_209_completed")) { throw "Unexpected finalizer preview state." }
Assert-ManagedModeRunSafeJson $preview
Write-ManagedModeRunSmokeResult "managed-mode-run-finalizer-preview"
