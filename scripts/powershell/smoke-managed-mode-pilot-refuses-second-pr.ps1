. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
$gate = Invoke-ManagedModePilotJson "apply-gate" "low-docs" @("-StateDir", $stateDir)
if ([int]$gate.selected_workunit_count -ne 1) { throw "Expected one selected workunit before PR limit check." }
$result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-StateDir", $stateDir, "-SimulateApply")
if ([int]$result.pr_count -ne 1) { throw "Pilot must model exactly one PR." }
Write-ManagedModeSmokeResult "managed-mode-pilot-refuses-second-pr"
