. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "pilot-apply" "low-docs" @("-SimulateApply")
if (-not $result.pr_created -or [int]$result.pr_count -ne 1) { throw "Expected simulated one PR." }
Write-ManagedModeSmokeResult "managed-mode-pilot-apply-creates-one-pr"
