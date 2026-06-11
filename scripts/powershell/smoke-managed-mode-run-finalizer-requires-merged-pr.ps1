. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$result = Invoke-ManagedModeRunJson "run-finalizer-apply"
if ($result.ok -ne $false) { throw "Finalizer apply should refuse without merged PR." }
if ($result.final_state -notin @("held_waiting_human_pr_review", "finalizer_blocked")) { throw "Unexpected refusal state." }
Assert-ManagedModeRunSafeJson $result
Write-ManagedModeRunSmokeResult "managed-mode-run-finalizer-requires-merged-pr"
