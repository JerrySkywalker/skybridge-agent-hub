. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$summary = Invoke-ManagedModePilotJson "safe-summary"
if ($summary.general_apply -ne "disabled") { throw "Expected general apply disabled." }
if ($summary.can_start_managed_mode -ne $false) { throw "Managed mode must remain pilot-only." }
$workunitReadiness = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-workunit-queue.ps1" -Command readiness -Json | ConvertFrom-Json
if ($workunitReadiness.start_bounded_queue_apply_available -ne $false) { throw "Generic bounded queue apply became available." }
Write-ManagedModeSmokeResult "managed-mode-v1-general-apply-disabled"
