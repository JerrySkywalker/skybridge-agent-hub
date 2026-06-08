[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$source = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")
foreach ($needle in @(
  "worker_service_state: fixtureWorkerServiceState",
  'execution_disabled_until_goal: "super-197-multi-worker-readiness"',
  "can_start_one: false",
  "can_start_queue: false",
  "can_resume: false",
  "execution_disabled_until_goal_197"
)) {
  if ($source -notmatch [regex]::Escape($needle)) { throw "Queue readiness integration missing: $needle" }
}

[pscustomobject]@{
  ok = $true
  smoke = "queue-readiness-worker-service-integration"
  can_start_one = $false
  can_start_queue = $false
  can_resume = $false
  execution_disabled_until_goal = "super-197-multi-worker-readiness"
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
