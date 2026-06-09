. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate" "production"
if ($gate.can_run_pilot) { throw "Gate must reject production work." }
if (-not (@($gate.blockers) -match "task_type_not_allowed|risk_must_be_low|blocked_high_risk_surface")) { throw "Missing production blocker." }
Write-ManagedModeSmokeResult "managed-mode-v1-pilot-gate-rejects-production"
