param(
  [switch]$DryRun,
  [int]$Port = 0
)

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

if (-not $DryRun) {
  throw "smoke-edge-worker-loop.ps1 defaults to safe validation; pass -DryRun. Real Codex execution belongs in a bounded pilot."
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-edge-worker-loop-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-edge-worker-loop.sqlite"
$configFile = Join-Path $tempDir "edge-worker.json"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth | Out-Null

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "smoke-loop-project"; name = "Smoke Loop Project" } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/smoke-loop-project/control" @{ state = "running"; stop_requested = $false; max_tasks = 1 } | Out-Null

  @{
    worker_id = "smoke-loop-worker"
    name = "Smoke Loop Worker"
    project_id = "smoke-loop-project"
    repo_path = (Resolve-Path ".").Path
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

  $output = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 -ConfigFile $configFile -Loop -DryRun -PollIntervalSeconds 1 -IdleTimeoutSeconds 2 -Json
  $results = @($output | Where-Object { $_ -match "^\s*\{" } | ForEach-Object { $_ | ConvertFrom-Json })
  $final = $results[-1]
  if (-not $final.loop) { throw "Expected final loop result." }
  if ($final.stop_reason -ne "idle_timeout") { throw "Expected idle_timeout stop, got $($final.stop_reason)." }
  if (-not (Test-Path -LiteralPath $final.log_dir -PathType Container)) { throw "Expected loop log directory." }
  $log = Get-Content -Raw -LiteralPath (Join-Path $final.log_dir "loop.jsonl")
  if ($log -notmatch "loop_start" -or $log -notmatch "loop_stop" -or $log -notmatch "task_poll") {
    throw "Expected loop log to include start, poll and stop records."
  }

  [pscustomobject]@{
    ApiBase = $ApiBase
    StopReason = $final.stop_reason
    LogDir = $final.log_dir
    CodexExecuted = $false
  } | Format-List
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
}
