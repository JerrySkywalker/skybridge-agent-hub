. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "finalizer-preview"
if ($result.final_state -ne "managed_mode_pilot_completed") { throw "Finalizer preview did not confirm completion readiness/completion." }
if ($result.state.task_pr.number -ne 140 -or $result.state.task_pr.merged -ne $true) { throw "PR #140 was not confirmed merged." }
if (@($result.state.task_pr.changed_files) -notcontains "docs/managed-mode-pilot-orientation.md") { throw "PR #140 changed file mismatch." }
Assert-ManagedModeSafeJson $result
Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-pr140-merged"

