. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-SimulateApply")
if ($result.final_state -ne "held_waiting_human_pr_review") { throw "Expected human review hold after PR." }
Write-ManagedModeSmokeResult "managed-mode-pilot-stops-on-pr-created"
