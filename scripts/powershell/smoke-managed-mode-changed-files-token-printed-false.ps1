. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$result = Invoke-ManagedModePilotJson "changed-files-preview"
Assert-ManagedModeSafeJson $result
Write-ManagedModeSmokeResult "managed-mode-changed-files-token-printed-false"

