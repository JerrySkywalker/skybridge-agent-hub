. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$before = (git status --short | Out-String).Trim()
$preview = Invoke-ManagedModePilotJson "pilot-preview"
$after = (git status --short | Out-String).Trim()
if ($preview.no_mutation -ne $true) { throw "Pilot preview must advertise no_mutation." }
if ($before -ne $after) { throw "Pilot preview mutated worktree." }
Write-ManagedModeSmokeResult "managed-mode-v1-pilot-preview-no-mutation"
