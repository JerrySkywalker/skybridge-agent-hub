[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1") -Command start-standby -Apply -MaxHeartbeats 2 -IntervalSeconds 0 -Json | ConvertFrom-Json

if (-not $result.ok) { throw "standby heartbeat did not return ok=true" }
if ([string]$result.worker_service.mode -ne "standby") { throw "Expected standby mode." }
if ([string]::IsNullOrWhiteSpace([string]$result.worker_service.heartbeat_at)) { throw "Expected heartbeat_at." }
if ([bool]$result.task_claimed -or [bool]$result.task_created -or [bool]$result.task_executed) { throw "Heartbeat path claimed/created/executed a task." }
if ([bool]$result.codex_worker_execution_started -or [bool]$result.pr_created) { throw "Heartbeat path started Codex or created a PR." }
if ([bool]$result.worker_service.can_claim_tasks -or [bool]$result.worker_service.can_execute_tasks) { throw "Standby worker must not claim or execute." }

[pscustomobject]@{
  ok = $true
  smoke = "worker-standby-heartbeat"
  mode = $result.worker_service.mode
  heartbeat_at = $result.worker_service.heartbeat_at
  task_claimed = $false
  task_executed = $false
  codex_worker_execution_started = $false
  pr_created = $false
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
