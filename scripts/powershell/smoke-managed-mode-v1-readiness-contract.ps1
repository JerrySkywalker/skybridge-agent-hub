. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$readiness = Invoke-ManagedModePilotJson "readiness"
if ($readiness.schema -ne "skybridge.managed_mode_v1_readiness.v1") { throw "Unexpected readiness schema." }
if ($readiness.can_start_managed_mode -ne $false) { throw "General managed mode must not start." }
if ($readiness.general_bounded_queue_apply_enabled -ne $false) { throw "General bounded queue apply must remain disabled." }
if ($readiness.pilot_id -ne "managed-mode-pilot-208") { throw "Unexpected pilot id." }
Write-ManagedModeSmokeResult "managed-mode-v1-readiness-contract"
