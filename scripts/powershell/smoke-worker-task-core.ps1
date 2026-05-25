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

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-task-core-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-task-core.sqlite"
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
  $health = Wait-SkyBridgeHealth

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{
    project_id = "smoke-project"
    name = "Smoke Project"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects/smoke-project/goals" @{
    goal_id = "smoke-goal"
    title = "Smoke master goal"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{
    worker_id = "smoke-worker"
    name = "Smoke worker"
    capabilities = @("manual-execution", "tests")
  } | Out-Null
  $heartbeatResponse = Invoke-SkyBridgeJson "POST" "/v1/workers/smoke-worker/heartbeat" @{
    status_note = "ready"
  }
  $workerAfterHeartbeat = Invoke-SkyBridgeJson "GET" "/v1/workers/smoke-worker"
  if ($workerAfterHeartbeat.worker.status -ne "online") {
    throw "Expected smoke worker to be online before claim, got $($workerAfterHeartbeat.worker.status). Heartbeat: $($heartbeatResponse | ConvertTo-Json -Depth 8). Worker: $($workerAfterHeartbeat | ConvertTo-Json -Depth 8)"
  }
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{
    task_id = "smoke-task"
    project_id = "smoke-project"
    goal_id = "smoke-goal"
    title = "Complete smoke task"
    risk = "low"
    source = "manual"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/smoke-task/claim" @{
    worker_id = "smoke-worker"
  } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/smoke-task/complete" @{
    summary = "Smoke completed without Codex, Hermes or notification providers."
  } | Out-Null

  $summary = Invoke-SkyBridgeJson "GET" "/v1/summary"
  $workers = Invoke-SkyBridgeJson "GET" "/v1/workers/summary"
  $tasks = Invoke-SkyBridgeJson "GET" "/v1/tasks/summary"

  if ($workers.online -lt 1) { throw "Expected one online worker." }
  if ($tasks.completed -lt 1) { throw "Expected one completed task." }
  if ($summary.totals.tasks_completed -lt 1) { throw "Expected completed task in top-level summary." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Persistence = $health.persistence
    OnlineWorkers = $workers.online
    CompletedTasks = $tasks.completed
    LatestTaskEvent = $tasks.latest_event.type
    NoRealCodex = $true
    NoRealHermes = $true
    NoRealNotification = $true
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
