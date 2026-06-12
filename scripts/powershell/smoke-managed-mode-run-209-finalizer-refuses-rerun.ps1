. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$result = Invoke-ManagedModeRunJson "run-finalizer-apply"
if ($result.ok -ne $false) { throw "Expected duplicate finalizer apply refusal." }
if ($result.blockers -notcontains "managed_mode_run_209_already_completed") { throw "Expected already completed blocker." }
Assert-ManagedModeRunSafeJson $result
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-refuses-rerun"
