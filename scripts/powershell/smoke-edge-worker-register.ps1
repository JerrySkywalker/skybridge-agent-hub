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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-edge-worker-register-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-edge-worker-register.sqlite"
$configFile = Join-Path $tempDir "edge-worker.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  @{
    worker_id = "smoke-edge-worker"
    name = "Smoke Edge Worker"
    project_id = "smoke-project"
    repo_path = (Resolve-Path ".").Path
    api_base = $ApiBase
    poll_interval_seconds = 5
    capabilities = @("codex-exec", "filesystem", "git", "tests", "docs")
    allowed_task_types = @("docs")
    blocked_task_types = @("deploy", "secrets", "production")
    codex_command = "codex"
    codex_sandbox = "danger-full-access"
    max_task_runtime_minutes = 5
    auto_merge_enabled = $false
    notification_enabled = $false
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $configFile -Encoding UTF8

  $workerOutput = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 -ConfigFile $configFile -Register -Heartbeat -Json
  $workerResult = $workerOutput | ConvertFrom-Json
  if (-not $workerResult.ok) { throw "Worker register/heartbeat command failed." }

  $worker = Invoke-SkyBridgeJson "GET" "/v1/workers/smoke-edge-worker"
  $workers = Invoke-SkyBridgeJson "GET" "/v1/workers/summary"
  if ($worker.worker.status -ne "online") { throw "Expected smoke-edge-worker to be online, got $($worker.worker.status)." }
  if ($workers.online -lt 1) { throw "Expected at least one online worker." }

  [pscustomobject]@{
    ApiBase = $ApiBase
    WorkerId = $worker.worker.worker_id
    Status = $worker.worker.status
    OnlineWorkers = $workers.online
    CodexExecuted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
