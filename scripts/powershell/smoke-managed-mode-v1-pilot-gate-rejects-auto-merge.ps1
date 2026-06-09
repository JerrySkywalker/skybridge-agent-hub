. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate" "auto-merge"
if ($gate.can_run_pilot) { throw "Gate must reject auto-merge." }
if ("auto_merge_forbidden" -notin @($gate.blockers)) { throw "Missing auto-merge blocker." }
Write-ManagedModeSmokeResult "managed-mode-v1-pilot-gate-rejects-auto-merge"
