. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$gate = Invoke-ManagedModeRunJson "next-run-gate"
if ($gate.can_run_one_at_a_time -ne $false) { throw "Expected duplicate managed-mode-run-209 apply gate blocked." }
if ($gate.blockers -notcontains "completed_run_id_reuse_blocked") { throw "Expected completed run id reuse blocker." }
Assert-ManagedModeRunSafeJson $gate
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-blocks-duplicate-apply"
