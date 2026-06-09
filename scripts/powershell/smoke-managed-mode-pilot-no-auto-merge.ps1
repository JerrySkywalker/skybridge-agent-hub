. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-SimulateApply")
if ($result.auto_merge_enabled) { throw "Auto-merge must be disabled." }
$blocked = Invoke-ManagedModePilotJson "apply-gate" "auto-merge"
if ($blocked.can_run_pilot) { throw "Auto-merge scenario must be blocked." }
Write-ManagedModeSmokeResult "managed-mode-pilot-no-auto-merge"
