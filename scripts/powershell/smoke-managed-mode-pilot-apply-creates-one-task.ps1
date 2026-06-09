. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-SimulateApply")
if (-not $result.task_created -or $result.task_id -ne "managed-mode-pilot-208-task-001") { throw "Expected simulated one task." }
Write-ManagedModeSmokeResult "managed-mode-pilot-apply-creates-one-task"
