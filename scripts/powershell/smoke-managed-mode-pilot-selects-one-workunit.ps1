. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$preview = Invoke-ManagedModePilotJson "pilot-preview"
if ([int]$preview.request.selected_workunit_count -ne 1) { throw "Expected exactly one selected workunit." }
Write-ManagedModeSmokeResult "managed-mode-pilot-selects-one-workunit"
