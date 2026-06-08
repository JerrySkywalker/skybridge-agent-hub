[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1") -Command readiness -Json | ConvertFrom-Json
foreach ($field in @("clean_worktree", "known_campaign", "active_tasks", "stale_leases", "runner_lock_status", "token_available", "worker_profile_valid")) {
  if (-not $result.readiness.PSObject.Properties[$field]) { throw "Missing readiness gate field: $field" }
}
if ([bool]$result.readiness.ready_for_start_one_gate) { throw "Goal 195 must not mark Start One gate ready." }
if (@($result.readiness.blockers) -notcontains "execution_disabled_until_goal_197") { throw "Missing later-gate execution blocker." }

[pscustomobject]@{
  ok = $true
  smoke = "worker-readiness-gates"
  ready_for_start_one_gate = $false
  can_claim_tasks = $false
  can_execute_tasks = $false
  blockers = @($result.readiness.blockers)
  token_printed = $false
} | ConvertTo-Json -Depth 20 -Compress
