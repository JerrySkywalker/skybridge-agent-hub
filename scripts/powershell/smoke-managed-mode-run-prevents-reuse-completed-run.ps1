. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$gate = Invoke-ManagedModeRunJson "next-run-gate" -Extra @("-ManagedModeRunId", "managed-mode-pilot-208")
if ($gate.can_run_one_at_a_time) { throw "Completed run id reuse must be blocked." }
if ($gate.blockers -notcontains "completed_run_id_reuse_blocked") { throw "Missing completed run id reuse blocker." }
Write-ManagedModeRunSmokeResult "managed-mode-run-prevents-reuse-completed-run"
