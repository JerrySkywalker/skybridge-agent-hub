. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate" "second-workunit"
if ($gate.can_run_pilot) { throw "Gate must reject multiple workunits." }
if ("max_workunits_must_equal_1" -notin @($gate.blockers)) { throw "Missing one-workunit blocker." }
Write-ManagedModeSmokeResult "managed-mode-v1-pilot-gate-one-workunit-only"
