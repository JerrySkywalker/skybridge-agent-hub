[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1") -Command stop -Apply -Reason "smoke stop request" -Json | ConvertFrom-Json
if (-not [bool]$result.worker_service.stop_requested) { throw "Expected stop_requested=true." }
if ([string]$result.worker_service.mode -ne "stopping") { throw "Expected stopping mode." }
if ([bool]$result.task_claimed -or [bool]$result.task_executed -or [bool]$result.codex_worker_execution_started) { throw "Stop requested path executed work." }

[pscustomobject]@{
  ok = $true
  smoke = "worker-service-stop-requested"
  mode = $result.worker_service.mode
  stop_requested = $true
  task_claimed = $false
  task_executed = $false
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
