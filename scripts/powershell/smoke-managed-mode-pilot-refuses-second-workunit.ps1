. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "pilot-apply" "second-workunit" @("-SimulateApply")
if ($result.ok) { throw "Second workunit must be refused." }
if ("max_workunits_must_equal_1" -notin @($result.blockers)) { throw "Missing second-workunit blocker." }
Write-ManagedModeSmokeResult "managed-mode-pilot-refuses-second-workunit"
