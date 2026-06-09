. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate" "secrets"
if ($gate.can_run_pilot) { throw "Gate must reject secret work." }
if (-not (@($gate.blockers) -match "blocked_secret_surface|risk_must_be_low|task_type_not_allowed")) { throw "Missing secret blocker." }
Write-ManagedModeSmokeResult "managed-mode-v1-pilot-gate-rejects-secrets"
