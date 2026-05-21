param(
  [string]$ApiBase = "http://127.0.0.1:8787",
  [switch]$StartServer,
  [int]$Port = 8799,
  [switch]$UseTempDatabase,
  [switch]$SkipWebBuildArtifactsCheck
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path) {
  Invoke-RestMethod -Method $Method -Uri "$ApiBase$Path"
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
      return Invoke-SkyBridgeJson "GET" "/v1/health"
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }

  throw "SkyBridge server did not become healthy at $ApiBase."
}

$serverProcess = $null
$tempDir = $null
$dbFile = $null

try {
  if ($UseTempDatabase) {
    $StartServer = $true
    $ApiBase = "http://127.0.0.1:$Port"
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-console-smoke-" + [Guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $dbFile = Join-Path $tempDir "skybridge-smoke.sqlite"
  }

  if ($StartServer) {
    if (-not $dbFile) {
      $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-console-smoke-" + [Guid]::NewGuid().ToString("n"))
      New-Item -ItemType Directory -Path $tempDir | Out-Null
      $dbFile = Join-Path $tempDir "skybridge-smoke.sqlite"
    }

    $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
    $serverProcess = Start-Process -FilePath "pwsh" -ArgumentList @("-NoProfile", "-Command", $serverCommand) -PassThru -WindowStyle Hidden
    $ApiBase = "http://127.0.0.1:$Port"
  }

  $health = Wait-SkyBridgeHealth

  & "$PSScriptRoot\seed-demo-events.ps1" -ApiBase $ApiBase | Out-Null

  $events = Invoke-SkyBridgeJson "GET" "/v1/events?limit=100"
  $runs = Invoke-SkyBridgeJson "GET" "/v1/runs?limit=50"
  $failedRuns = Invoke-SkyBridgeJson "GET" "/v1/runs?status=failed"
  $notifications = Invoke-SkyBridgeJson "GET" "/v1/notifications?limit=50"
  $summary = Invoke-SkyBridgeJson "GET" "/v1/summary"

  if ($events.events.Count -lt 8) {
    throw "Expected at least 8 demo events, got $($events.events.Count)."
  }
  if ($runs.runs.Count -lt 3) {
    throw "Expected at least 3 demo runs, got $($runs.runs.Count)."
  }
  if ($failedRuns.runs.Count -lt 1) {
    throw "Expected at least one failed run."
  }
  if ($summary.totals.attention_items -lt 1) {
    throw "Expected at least one attention item."
  }

  $webIndex = Join-Path (Get-Location) "apps\web\dist\index.html"
  $webBuildPresent = Test-Path -LiteralPath $webIndex
  if (-not $SkipWebBuildArtifactsCheck -and -not $webBuildPresent) {
    throw "Web build artifact not found at $webIndex. Run corepack pnpm --filter @skybridge-agent-hub/web build first, or pass -SkipWebBuildArtifactsCheck."
  }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Persistence = $health.persistence
    Events = $events.events.Count
    Runs = $runs.runs.Count
    FailedRuns = $failedRuns.runs.Count
    Notifications = $notifications.notifications.Count
    AttentionItems = $summary.totals.attention_items
    WebBuildPresent = $webBuildPresent
    DbFile = $dbFile
  } | Format-List
} finally {
  if ($serverProcess) {
    Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
  }
}
