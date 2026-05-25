param(
  [int]$Port = 0,
  [switch]$SkipWebBuild
)

$ErrorActionPreference = "Stop"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path) {
  Invoke-RestMethod -Method $Method -Uri "$ApiBase$Path"
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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-product-console-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-product-console.sqlite"
if ($Port -le 0) {
  $Port = Get-Random -Minimum 18000 -Maximum 28000
}
$ApiBase = "http://127.0.0.1:$Port"

try {
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
  $health = Wait-SkyBridgeHealth

  & "$PSScriptRoot\seed-demo-events.ps1" -ApiBase $ApiBase | Out-Null

  $summary = Invoke-SkyBridgeJson "GET" "/v1/summary"
  $projects = Invoke-SkyBridgeJson "GET" "/v1/projects"
  $iterations = Invoke-SkyBridgeJson "GET" "/v1/iterations/summary"
  $prs = Invoke-SkyBridgeJson "GET" "/v1/prs/summary"
  $notifications = Invoke-SkyBridgeJson "GET" "/v1/notifications/summary"
  $hermes = Invoke-SkyBridgeJson "GET" "/v1/hermes/summary"
  $automerge = Invoke-SkyBridgeJson "GET" "/v1/automerge/summary"
  $audit = Invoke-SkyBridgeJson "GET" "/v1/audit?limit=20"

  if ($prs.total -lt 2) { throw "Expected at least two PR records in product summary." }
  if ($iterations.total -lt 2) { throw "Expected seeded iteration summary." }
  if ($prs.blocked -lt 1) { throw "Expected blocked PR summary." }
  if ($notifications.failed -lt 1) { throw "Expected failed notification summary." }
  if ($hermes.status -ne "degraded") { throw "Expected Hermes degraded demo status, got $($hermes.status)." }
  if ($automerge.dry_run_default -ne $true) { throw "Expected auto-merge dry-run default." }
  if ($audit.audit.Count -lt 1) { throw "Expected audit records from seeded failure/notification events." }

  if (-not $SkipWebBuild) {
    corepack pnpm --filter @skybridge-agent-hub/web build | Out-Host
  }

  $webIndex = Join-Path (Get-Location) "apps\web\dist\index.html"
  if (-not (Test-Path -LiteralPath $webIndex)) {
    throw "Web build artifact not found at $webIndex."
  }
  $webText = Get-Content -Raw -LiteralPath $webIndex
  if ($webText -notmatch "root") {
    throw "Web build index does not contain the app root."
  }

  [pscustomobject]@{
    ApiBase = $ApiBase
    Persistence = $health.persistence
    DbFile = $dbFile
    OpenPrs = $summary.totals.open_prs
    Iterations = $iterations.total
    BlockedPrs = $prs.blocked
    NotificationFailed = $notifications.failed
    Hermes = $hermes.status
    AutoMergeDryRunDefault = $automerge.dry_run_default
    AuditRecords = $audit.audit.Count
    WebBuildPresent = $true
  } | Format-List
} finally {
  if ($serverProcess) {
    try {
      $serverProcess.Kill($true)
    } catch {
      Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
  }
}
