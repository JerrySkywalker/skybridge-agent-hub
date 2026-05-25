param(
  [int]$Port = 0
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
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-adapter-registry-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$dbFile = Join-Path $tempDir "skybridge-adapter-registry.sqlite"
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
  Wait-SkyBridgeHealth | Out-Null

  $registry = Invoke-SkyBridgeJson "GET" "/v1/adapters"
  $adapters = @($registry.adapters)
  foreach ($id in @("rule-based-planner", "hermes-api", "manual-executor", "codex-exec-json", "github-actions", "generic-scm", "ntfy", "generic-notification", "sidecar")) {
    if (-not ($adapters | Where-Object { $_.id -eq $id })) {
      throw "Adapter registry missing $id."
    }
  }

  $planners = Invoke-SkyBridgeJson "GET" "/v1/adapters?role=planner"
  if (@($planners.adapters | Where-Object { $_.role -ne "planner" }).Count -gt 0) {
    throw "Planner registry role filter returned non-planner entries."
  }

  [pscustomobject]@{
    ApiBase = $ApiBase
    AdapterCount = $adapters.Count
    PlannerAdapters = @($adapters | Where-Object { $_.role -eq "planner" }).Count
    ExecutorAdapters = @($adapters | Where-Object { $_.role -eq "executor" }).Count
    NotificationProviders = @($adapters | Where-Object { $_.role -eq "notification_provider" }).Count
    AllOptional = -not (@($adapters | Where-Object { $_.optional -ne $true }).Count)
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
