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

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-loop-control-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$repoDir = Join-Path $tempDir "repo"
New-Item -ItemType Directory -Path $repoDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-worker-loop-control.sqlite"
$configFile = Join-Path $tempDir "edge-worker.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  git -C $repoDir init -b main | Out-Null
  git -C $repoDir config user.email "skybridge-smoke@example.invalid" | Out-Null
  git -C $repoDir config user.name "SkyBridge Smoke" | Out-Null
  Set-Content -LiteralPath (Join-Path $repoDir "README.md") -Value "# Smoke repo" -Encoding UTF8
  git -C $repoDir add README.md | Out-Null
  git -C $repoDir commit -m "Initialize smoke repo" | Out-Null

  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "smoke-worker-loop-control"; name = "Smoke Worker Loop Control" } | Out-Null

  @{
    worker_id = "smoke-loop-control-worker"
    name = "Smoke Loop Control Worker"
    project_id = "smoke-worker-loop-control"
    repo_path = $repoDir
    api_base = $ApiBase
    poll_interval_seconds = 1
    capabilities = @("codex-exec", "filesystem", "git", "tests", "docs")
    allowed_task_types = @("docs")
    blocked_task_types = @("deploy", "secrets", "production")
    codex_command = "codex"
    codex_sandbox = "danger-full-access"
    max_task_runtime_minutes = 5
    auto_merge_enabled = $false
    notification_enabled = $false
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $configFile -Encoding UTF8

  $output = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
    -ConfigFile $configFile `
    -Loop `
    -MaxTasks 1 `
    -IdleTimeoutSeconds 1 `
    -PollIntervalSeconds 1 `
    -StopOnFailure `
    -Json
  $results = @($output | Where-Object { $_ -match "^\s*\{" } | ForEach-Object { $_ | ConvertFrom-Json })
  $final = $results[-1]
  if (-not $final.loop) { throw "Expected final loop result." }
  if ($final.stop_reason -ne "idle_timeout") { throw "Expected idle_timeout stop, got $($final.stop_reason)." }
  if ($final.completed_tasks -ne 0) { throw "Expected no completed tasks in empty queue smoke." }

  $control = (Invoke-SkyBridgeJson "GET" "/v1/projects/smoke-worker-loop-control/control").control_state
  if ($control.state -ne "paused") { throw "Expected final project control state paused, got $($control.state)." }
  if ([bool]$control.stop_requested) { throw "Expected stop_requested=false after loop finalization." }
  if ([int]$control.max_tasks -ne 1) { throw "Expected max_tasks=1, got $($control.max_tasks)." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    StopReason = $final.stop_reason
    FinalState = $control.state
    StopRequested = [bool]$control.stop_requested
    MaxTasks = [int]$control.max_tasks
    CompletedTasks = [int]$final.completed_tasks
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path -LiteralPath $tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
