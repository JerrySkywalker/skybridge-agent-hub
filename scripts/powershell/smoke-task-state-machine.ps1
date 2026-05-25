param(
  [int]$Port = 0
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -eq "POST" -or $Method -eq "PATCH") {
      return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}"
    }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12)
}

function Invoke-ExpectFailure([scriptblock]$Script, [string]$Label) {
  try {
    & $Script | Out-Null
  } catch {
    return
  }
  throw "Expected failure: $Label"
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-task-state-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-task-state.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{
    FilePath = "pwsh"
    ArgumentList = @("-NoProfile", "-Command", $serverCommand)
    PassThru = $true
  }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "state-project"; name = "State Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "state-worker"; name = "State worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/state-worker/heartbeat" @{} | Out-Null
  $stateWorker = Invoke-SkyBridgeJson "GET" "/v1/workers/state-worker"
  if ($stateWorker.worker.status -ne "online") {
    throw "Expected state worker to be online before claim, got $($stateWorker.worker.status)."
  }
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "disabled-worker"; name = "Disabled worker"; enabled = $false } | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "task-complete"; project_id = "state-project"; title = "Complete" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/task-complete/claim" @{ worker_id = "state-worker" } | Out-Null
  $completed = Invoke-SkyBridgeJson "POST" "/v1/tasks/task-complete/complete" @{ summary = "done" }
  if ($completed.task.status -ne "completed") { throw "Expected completed status." }

  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "task-requeue"; project_id = "state-project"; title = "Requeue" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/task-requeue/claim" @{ worker_id = "state-worker" } | Out-Null
  $failed = Invoke-SkyBridgeJson "POST" "/v1/tasks/task-requeue/fail" @{ error_summary = "fixture failure" }
  if ($failed.task.status -ne "failed") { throw "Expected failed status." }
  $requeued = Invoke-SkyBridgeJson "POST" "/v1/tasks/task-requeue/requeue"
  if ($requeued.task.status -ne "queued") { throw "Expected requeued status." }

  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "task-blocked"; project_id = "state-project"; title = "Block" } | Out-Null
  $blocked = Invoke-SkyBridgeJson "POST" "/v1/tasks/task-blocked/block" @{ error_summary = "operator review" }
  if ($blocked.task.status -ne "blocked") { throw "Expected blocked status." }

  Invoke-ExpectFailure { Invoke-SkyBridgeJson "POST" "/v1/tasks/task-complete/claim" @{ worker_id = "state-worker" } } "completed cannot be claimed"
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "task-disabled"; project_id = "state-project"; title = "Disabled claim" } | Out-Null
  Invoke-ExpectFailure { Invoke-SkyBridgeJson "POST" "/v1/tasks/task-disabled/claim" @{ worker_id = "disabled-worker" } } "disabled worker cannot claim"

  $tasks = Invoke-SkyBridgeJson "GET" "/v1/tasks/summary"
  if ($tasks.completed -lt 1 -or $tasks.blocked -lt 1 -or $tasks.queued -lt 1) {
    throw "Expected completed, blocked and queued task counts."
  }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Completed = $tasks.completed
    Failed = $tasks.failed
    Blocked = $tasks.blocked
    Queued = $tasks.queued
    StateMachine = "passed"
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
