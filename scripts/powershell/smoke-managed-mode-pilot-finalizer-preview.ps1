. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$preview = Invoke-ManagedModePilotJson "finalizer-preview"
if ($preview.final_state -ne "managed_mode_pilot_completed") { throw "Finalizer preview should confirm merged PR completion readiness." }
if ($preview.state.task_pr.number -ne 140 -or $preview.state.task_pr.merged -ne $true) { throw "Finalizer preview did not confirm merged PR #140." }
if ($preview.no_mutation -ne $true) { throw "Finalizer preview must be read-only." }
Assert-ManagedModeSafeJson $preview
Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-preview"
