param([int]$Port = 0)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) {
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

function Invoke-ControlCli([string]$Area, [string]$Command, [hashtable]$Extra = @{}) {
  $args = @(
    "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\skybridge-hermes-cli.ps1",
    "-Area", $Area,
    "-Command", $Command,
    "-ApiBase", $ApiBase,
    "-ProjectId", "smoke-control-project",
    "-GoalId", "smoke-control-goal",
    "-Json"
  )
  foreach ($key in $Extra.Keys) {
    $args += "-$key"
    $args += [string]$Extra[$key]
  }
  return (& pwsh @args) | ConvertFrom-Json
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-control-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-control.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "smoke-control-project"; name = "Smoke Control Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects/smoke-control-project/goals" @{ goal_id = "smoke-control-goal"; title = "Smoke control goal" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "smoke-control-worker"; name = "Smoke control worker"; capabilities = @("docs") } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/smoke-control-worker/heartbeat" @{ status_note = "ready" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = "smoke-control-task"; project_id = "smoke-control-project"; goal_id = "smoke-control-goal"; title = "Smoke control task"; risk = "low"; source = "manual" } | Out-Null

  $started = Invoke-ControlCli "project" "start" @{ MaxTasks = 2 }
  if ($started.control_state.state -ne "running") { throw "Expected running control state." }
  $paused = Invoke-ControlCli "project" "pause"
  if ($paused.control_state.state -ne "paused") { throw "Expected paused control state." }
  $resumed = Invoke-ControlCli "project" "resume"
  if ($resumed.control_state.state -ne "running") { throw "Expected resumed running control state." }
  $stopped = Invoke-ControlCli "project" "stop"
  if ($stopped.control_state.state -ne "stopped" -or -not $stopped.control_state.stop_requested) { throw "Expected stopped control state with stop request." }
  $status = Invoke-ControlCli "project" "status"
  $workers = Invoke-ControlCli "workers" "list"
  $tasks = Invoke-ControlCli "tasks" "list"
  $task = Invoke-ControlCli "task" "show" @{ TaskId = "smoke-control-task" }

  if (-not $status.control.control_state) { throw "Expected status to include control state." }
  if (@($workers.workers).Count -lt 1) { throw "Expected worker list." }
  if (@($tasks.tasks).Count -lt 1) { throw "Expected task list." }
  if ($task.task.task_id -ne "smoke-control-task") { throw "Expected task show result." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    ControlState = $stopped.control_state.state
    StopRequested = $stopped.control_state.stop_requested
    Workers = @($workers.workers).Count
    Tasks = @($tasks.tasks).Count
    CodexExecuted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
