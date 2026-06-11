. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$gate = Invoke-ManagedModeRunJson "next-run-gate" -Extra @("-SimulateOpenRun")
if ($gate.can_run_one_at_a_time) { throw "Duplicate open run must be blocked." }
if ($gate.blockers -notcontains "duplicate_open_run_blocked") { throw "Missing duplicate open run blocker." }
Write-ManagedModeRunSmokeResult "managed-mode-run-prevents-duplicate-open-run"
