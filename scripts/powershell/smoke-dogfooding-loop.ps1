param(
  [string]$ApiBase = "http://127.0.0.1:8787",
  [switch]$StartServer,
  [int]$Port = 0
)

$ErrorActionPreference = "Stop"

function Send-Event {
  param([hashtable]$Event)
  Invoke-RestMethod -Method Post -Uri "$ApiBase/v1/events" -ContentType "application/json" -Body ($Event | ConvertTo-Json -Depth 20) | Out-Null
}

function New-Event {
  param([string]$Type, [string]$RunId, [hashtable]$Payload, [string]$Severity = "info")
  @{
    schema = "skybridge.agent_event.v1"
    time = (Get-Date).ToUniversalTime().ToString("o")
    type = $Type
    severity = $Severity
    source = @{ platform = "skybridge"; adapter = "dogfooding-smoke" }
    correlation = @{ run_id = $RunId; session_id = "dogfooding-session" }
    payload = $Payload + @{ category = "dogfooding"; raw_output_omitted = $true }
  }
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
      return Invoke-RestMethod "$ApiBase/v1/health"
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
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-dogfood-smoke-" + [Guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $dbFile = Join-Path $tempDir "skybridge-dogfood.sqlite"
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

  $health = Wait-SkyBridgeHealth
  if (-not $health.ok) { throw "SkyBridge health check failed" }

  $runId = "dogfooding-$(Get-Date -Format yyyyMMddHHmmss)"
  Send-Event (New-Event "run.started" $runId @{ title = "SkyBridge dogfooding loop"; lifecycle = "started" })
  Send-Event (New-Event "tool.completed" $runId @{ tool_name = "codex-hook-smoke"; exit_code = 0 })
  Send-Event (New-Event "notification.requested" $runId @{ title = "Dogfooding notification job"; body = "safe fixture" } "warning")
  Send-Event (New-Event "run.completed" $runId @{ lifecycle = "completed" })

  $run = Invoke-RestMethod "$ApiBase/v1/runs/$runId"
  $notifications = Invoke-RestMethod "$ApiBase/v1/notifications?limit=20"
  $audit = Invoke-RestMethod "$ApiBase/v1/audit"

  if ($run.summary.run_id -ne $runId) { throw "Run detail did not return dogfooding run" }
  if ($audit.audit.Count -lt 1) { throw "Expected dogfooding events to produce audit records." }

  Write-Host "Dogfooding smoke passed for $runId"
  Write-Host "Notifications observed: $($notifications.notifications.Count)"
  Write-Host "Audit records observed: $($audit.audit.Count)"
} finally {
  if ($serverProcess) {
    try {
      $serverProcess.Kill($true)
    } catch {
      Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
  }
  if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempDir)
    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
  }
}
