[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$source = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")

foreach ($needle in @(
  "skybridge.worker_service_state.v1",
  "worker_service_state",
  "worker_id",
  "worker_profile",
  "heartbeat_at",
  "service_started_at",
  "current_task_id",
  "can_claim_tasks: false",
  "can_execute_tasks: false",
  "capability_matrix",
  "readiness_blockers",
  "execution_disabled_until_goal_199",
  "token_printed: false"
)) {
  if ($source -notmatch [regex]::Escape($needle)) { throw "Missing worker service contract field: $needle" }
}

[pscustomobject]@{
  ok = $true
  smoke = "worker-service-contract"
  schema = "skybridge.worker_service_state.v1"
  can_claim_tasks = $false
  can_execute_tasks = $false
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
