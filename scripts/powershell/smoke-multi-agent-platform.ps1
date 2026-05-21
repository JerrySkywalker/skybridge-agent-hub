param(
  [string]$ApiBase = "http://127.0.0.1:8787",
  [switch]$StartServer,
  [int]$Port = 0
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, [object]$Body = $null) {
  $params = @{
    Method = $Method
    Uri = "$ApiBase$Path"
  }
  if ($null -ne $Body) {
    $params.ContentType = "application/json"
    $params.Body = ($Body | ConvertTo-Json -Depth 20)
  }
  Invoke-RestMethod @params
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
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

try {
  if ($StartServer) {
    if ($Port -le 0) {
      $Port = Get-Random -Minimum 18000 -Maximum 28000
    }
    $ApiBase = "http://127.0.0.1:$Port"
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-multi-agent-" + [Guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $dbFile = Join-Path $tempDir "skybridge-multi-agent.sqlite"
    $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; corepack pnpm --filter @skybridge-agent-hub/server dev"
    $startProcessParams = @{
      FilePath = "pwsh"
      ArgumentList = @("-NoProfile", "-Command", $serverCommand)
      PassThru = $true
    }
    if ($IsWindows) {
      $startProcessParams.WindowStyle = "Hidden"
    }
    $serverProcess = Start-Process @startProcessParams
  }

  Wait-SkyBridgeHealth | Out-Null

  $events = Get-Content .\docs\demo\skybridge-demo-events.json -Raw | ConvertFrom-Json
  foreach ($event in $events) {
    Invoke-SkyBridgeJson "POST" "/v1/events" $event | Out-Null
  }

  $sources = Invoke-SkyBridgeJson "GET" "/v1/sources"
  $metrics = Invoke-SkyBridgeJson "GET" "/v1/metrics"
  $nodes = Invoke-SkyBridgeJson "GET" "/v1/nodes"
  $providers = Invoke-SkyBridgeJson "GET" "/v1/notifications/providers"
  $approvals = Invoke-SkyBridgeJson "GET" "/v1/approvals"

  foreach ($platform in @("codex", "opencode", "hermes", "skybridge", "custom")) {
    if (-not ($sources.sources | Where-Object { $_.platform -eq $platform })) {
      throw "Missing source capability for $platform"
    }
  }
  if ($metrics.total_events -lt 8) {
    throw "Expected at least 8 events in metrics, got $($metrics.total_events)"
  }
  if (-not $nodes.nodes -or $nodes.nodes.Count -lt 1) {
    throw "Expected node summary from demo heartbeat"
  }
  if (-not ($providers.providers | Where-Object { $_.provider -eq "ntfy" })) {
    throw "Expected ntfy provider status"
  }
  if (-not ($approvals.approvals | Where-Object { $_.approval_id -eq "demo-approval-1" })) {
    throw "Expected demo approval request"
  }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Events = $metrics.total_events
    Sources = $sources.sources.Count
    Nodes = $nodes.nodes.Count
    Providers = $providers.providers.Count
    PendingApprovals = $approvals.approvals.Count
  } | Format-List
} finally {
  if ($serverProcess) {
    try {
      $serverProcess.Kill($true)
    } catch {
      Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
  }
  if ($tempDir) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
