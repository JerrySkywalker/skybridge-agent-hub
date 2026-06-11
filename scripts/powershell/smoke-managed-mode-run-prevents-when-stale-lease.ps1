. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$gate = Invoke-ManagedModeRunJson "next-run-gate" -Extra @("-StaleLeases", "1")
if ($gate.can_run_one_at_a_time) { throw "Stale leases must block next run." }
if ($gate.blockers -notcontains "stale_leases_present") { throw "Missing stale lease blocker." }
Write-ManagedModeRunSmokeResult "managed-mode-run-prevents-when-stale-lease"
