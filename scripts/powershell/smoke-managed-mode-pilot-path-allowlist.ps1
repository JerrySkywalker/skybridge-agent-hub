. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$blocked = Invoke-ManagedModePilotJson "apply-gate" "bad-path"
if ($blocked.can_run_pilot) { throw "Bad path scenario must be blocked." }
if (-not (@($blocked.blockers) -match "path_allowlist_violation")) { throw "Missing path allowlist blocker." }
Write-ManagedModeSmokeResult "managed-mode-pilot-path-allowlist"
