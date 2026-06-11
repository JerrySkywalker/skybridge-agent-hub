. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$result = Invoke-ManagedModeRunJson "run-apply" -Extra @("-Authorize209B", "-AuthorizationReason", "fixture dry-run authorization", "-SimulateApply")
if ($result.final_state -ne "held_waiting_human_pr_review" -or $result.stop_on_pr_created -ne $true) { throw "209 dry-run must stop on PR creation." }
Write-ManagedModeRunSmokeResult "managed-mode-run-209-stops-on-pr-created"
