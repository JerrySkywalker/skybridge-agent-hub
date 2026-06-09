. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate" "second-workunit"
if ($gate.general_bounded_queue_apply_enabled) { throw "General bounded queue apply must be disabled." }
if ($gate.can_run_pilot) { throw "Unbounded queue scenario must not pass." }
Write-ManagedModeSmokeResult "managed-mode-v1-no-unbounded-queue"
