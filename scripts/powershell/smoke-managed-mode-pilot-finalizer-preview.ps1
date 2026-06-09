. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$preview = Invoke-ManagedModePilotJson "finalizer-preview"
if ($preview.final_state -ne "held_waiting_human_pr_review") { throw "Finalizer preview should hold without merged pilot PR evidence." }
if ($preview.no_mutation -ne $true) { throw "Finalizer preview must be read-only." }
Assert-ManagedModeSafeJson $preview
Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-preview"
