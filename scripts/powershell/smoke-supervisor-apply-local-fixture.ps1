param([int]$Port = 0)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 16)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try { return Invoke-SkyBridgeJson "GET" "/v1/health" } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-supervisor-apply-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-supervisor-apply.sqlite"
$outputDir = Join-Path $tempDir "snapshots"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "supervisor-apply-project"; name = "Supervisor Apply Project" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "supervisor-worker"; name = "Supervisor Worker"; capabilities = @("codex") } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/supervisor-worker/heartbeat" @{ status_note = "fixture" } | Out-Null

  $result = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-supervise.ps1 `
    -ApiBase $ApiBase `
    -ProjectId supervisor-apply-project `
    -MasterGoalId supervisor-apply-master `
    -GoalTitle "Supervisor apply fixture goal" `
    -Apply `
    -NoRun `
    -OutputDir $outputDir `
    -Json | ConvertFrom-Json
  $tasks = Invoke-SkyBridgeJson "GET" "/v1/tasks?project_id=supervisor-apply-project"
  $control = Invoke-SkyBridgeJson "GET" "/v1/projects/supervisor-apply-project/control"
  $round = @($result.rounds)[0]

  if ($result.supervisor_run.mode -ne "apply") { throw "Expected apply supervisor mode." }
  if ($result.supervisor_run.stop_reason -ne "no_run") { throw "Expected no_run stop reason." }
  if (@($tasks.tasks).Count -ne 1) { throw "Expected one converted task." }
  if ($round.action -ne "convert" -or -not $round.selected_task_id) { throw "Expected converted task in round." }
  if ($control.control_state.state -ne "paused") { throw "Expected project control restored to paused." }
  if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Mode = $result.supervisor_run.mode
    StopReason = $result.supervisor_run.stop_reason
    ConvertedTasks = @($tasks.tasks).Count
    Control = $control.control_state.state
    TokenPrinted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
