param(
  [string]$ApiBase = "http://127.0.0.1:8787",
  [switch]$StartServer,
  [switch]$UseTempDatabase,
  [switch]$Reset,
  [string]$DbFile
)

$ErrorActionPreference = "Stop"

function New-IsoTime([int]$OffsetMinutes) {
  return (Get-Date).ToUniversalTime().AddMinutes($OffsetMinutes).ToString("o")
}

function New-SkyBridgeEvent(
  [string]$Id,
  [string]$Type,
  [string]$Severity,
  [string]$Platform,
  [string]$Adapter,
  [hashtable]$Correlation,
  [hashtable]$Payload,
  [int]$OffsetMinutes
) {
  return @{
    schema = "skybridge.agent_event.v1"
    event_id = $Id
    time = New-IsoTime $OffsetMinutes
    type = $Type
    severity = $Severity
    source = @{
      platform = $Platform
      adapter = $Adapter
      node_id = "demo-node"
      agent_id = "demo-agent"
      cwd = "V:\src\skybridge-agent-hub"
    }
    correlation = $Correlation
    payload = $Payload
  }
}

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri
  }

  $json = $Body | ConvertTo-Json -Depth 12
  return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body $json
}

$serverProcess = $null
$tempDir = $null

try {
  if ($UseTempDatabase) {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-demo-" + [Guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $DbFile = Join-Path $tempDir "skybridge-demo.sqlite"
    $StartServer = $true
  }

  if ($Reset -and $DbFile -and (Test-Path -LiteralPath $DbFile)) {
    Remove-Item -LiteralPath $DbFile -Force
    Remove-Item -LiteralPath "$DbFile-wal" -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$DbFile-shm" -Force -ErrorAction SilentlyContinue
  }

  if ($StartServer) {
    if (-not $DbFile) {
      throw "-StartServer requires -DbFile or -UseTempDatabase."
    }

    $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$DbFile'; `$env:PORT = '8787'; corepack pnpm --filter @skybridge-agent-hub/server dev"
    $startProcessParams = @{
      FilePath = "pwsh"
      ArgumentList = @("-NoProfile", "-Command", $serverCommand)
      PassThru = $true
    }
    if ($IsWindows) {
      $startProcessParams.WindowStyle = "Hidden"
    }
    $serverProcess = Start-Process @startProcessParams
    Start-Sleep -Seconds 4
  }

  $health = Invoke-SkyBridgeJson "GET" "/v1/health"
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
  $events = @(
    New-SkyBridgeEvent "demo-codex-hook-start-$stamp" "run.started" "info" "codex" "codex-hook" `
      @{ session_id = "demo-codex-session"; run_id = "demo-codex-hook-run" } `
      @{ title = "Codex hook demo"; branch = "ai/demo-operator-console"; goal = "Validate hook telemetry"; lifecycle = "hook.prompt.accepted"; spool_count = 0 } -12
    New-SkyBridgeEvent "demo-codex-hook-tool-$stamp" "tool.completed" "info" "codex" "codex-hook" `
      @{ session_id = "demo-codex-session"; run_id = "demo-codex-hook-run"; tool_call_id = "demo-read-docs" } `
      @{ tool = "shell"; command_summary = "Get-Content README.md"; output_present = $true; output_length = 420; redacted = $true } -11
    New-SkyBridgeEvent "demo-codex-exec-start-$stamp" "run.started" "info" "codex" "codex-exec-json" `
      @{ session_id = "demo-exec-session"; run_id = "demo-codex-exec-run" } `
      @{ title = "Codex exec demo"; branch = "ai/demo-operator-console"; goal = "Run focused checks"; lifecycle = "exec.started" } -10
    New-SkyBridgeEvent "demo-codex-exec-complete-$stamp" "run.completed" "info" "codex" "codex-exec-json" `
      @{ session_id = "demo-exec-session"; run_id = "demo-codex-exec-run" } `
      @{ lifecycle = "exec.completed"; summary = "Focused checks completed." } -9
    New-SkyBridgeEvent "demo-runner-start-$stamp" "run.started" "info" "skybridge" "yolo-runner" `
      @{ session_id = "demo-runner-session"; run_id = "demo-yolo-runner-run" } `
      @{ title = "Runner demo goal"; branch = "ai/demo-operator-console"; goalFile = "003-dashboard-productization.md"; goalId = "003"; lifecycle = "goal.claimed" } -8
    New-SkyBridgeEvent "demo-tool-failed-$stamp" "tool.failed" "error" "skybridge" "yolo-runner" `
      @{ session_id = "demo-runner-session"; run_id = "demo-yolo-runner-run"; tool_call_id = "demo-typecheck" } `
      @{ tool = "shell"; command_summary = "corepack pnpm typecheck"; exitCode = 2; output_present = $true; output_length = 880; redacted = $true } -7
    New-SkyBridgeEvent "demo-approval-$stamp" "approval.requested" "warning" "codex" "codex-hook" `
      @{ session_id = "demo-codex-session"; run_id = "demo-codex-hook-run"; tool_call_id = "demo-network" } `
      @{ reason = "Demo approval request for a network action"; command_summary = "Invoke-RestMethod http://127.0.0.1:8787/health"; redacted = $true } -6
    New-SkyBridgeEvent "demo-notification-requested-$stamp" "notification.requested" "warning" "skybridge" "yolo-runner" `
      @{ session_id = "demo-runner-session"; run_id = "demo-yolo-runner-run" } `
      @{ title = "Demo attention item"; message = "A demo runner event needs attention."; priority = "default" } -5
    New-SkyBridgeEvent "demo-notification-sent-$stamp" "notification.sent" "info" "skybridge" "notification-center" `
      @{ session_id = "demo-runner-session"; run_id = "demo-yolo-runner-run" } `
      @{ provider = "placeholder"; status = "skipped"; reason = "NTFY_TOPIC_URL is not configured in demo mode." } -4
    New-SkyBridgeEvent "demo-spool-offline-$stamp" "agent.stale" "warning" "codex" "codex-hook" `
      @{ session_id = "demo-codex-session"; run_id = "demo-codex-hook-run" } `
      @{ lifecycle = "spool.offline"; spool_count = 3; queued_spool_count = 3; redacted = $true } -3
    New-SkyBridgeEvent "demo-spool-replayed-$stamp" "agent.idle" "info" "codex" "codex-hook" `
      @{ session_id = "demo-codex-session"; run_id = "demo-codex-hook-run" } `
      @{ lifecycle = "spool.replayed"; replayed_count = 3; spool_count = 0; redacted = $true } -2
    New-SkyBridgeEvent "demo-runner-failed-$stamp" "run.failed" "error" "skybridge" "yolo-runner" `
      @{ session_id = "demo-runner-session"; run_id = "demo-yolo-runner-run" } `
      @{ lifecycle = "goal.failed"; summary = "Demo failure for Operator Console attention states."; redacted = $true } -1
  )

  foreach ($event in $events) {
    Invoke-SkyBridgeJson "POST" "/v1/events" $event | Out-Null
  }

  $runs = Invoke-SkyBridgeJson "GET" "/v1/runs?limit=20"
  $eventList = Invoke-SkyBridgeJson "GET" "/v1/events?limit=50"
  $notifications = Invoke-SkyBridgeJson "GET" "/v1/notifications?limit=20"

  [pscustomobject]@{
    ApiBase = $ApiBase
    Persistence = $health.persistence
    DbFile = $DbFile
    SeededEvents = $events.Count
    VisibleEvents = $eventList.events.Count
    Runs = $runs.runs.Count
    Notifications = $notifications.notifications.Count
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
