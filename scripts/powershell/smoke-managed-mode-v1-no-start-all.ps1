. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$schema = Invoke-ManagedModePilotJson "schema"
if ($schema.can_start_managed_mode -ne $false) { throw "start-all style managed mode must be disabled." }
Write-ManagedModeSmokeResult "managed-mode-v1-no-start-all"
