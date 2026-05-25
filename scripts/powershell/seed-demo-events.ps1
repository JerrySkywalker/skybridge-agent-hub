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
    New-SkyBridgeEvent "demo-opencode-start-$stamp" "run.started" "info" "opencode" "opencode-plugin" `
      @{ session_id = "demo-opencode-session"; run_id = "demo-opencode-run" } `
      @{ title = "OpenCode fixture adapter"; branch = "ai/demo-opencode"; goal = "Check adapter fixture"; lifecycle = "adapter.fixture" } -15
    New-SkyBridgeEvent "demo-opencode-complete-$stamp" "run.completed" "info" "opencode" "opencode-plugin" `
      @{ session_id = "demo-opencode-session"; run_id = "demo-opencode-run" } `
      @{ lifecycle = "adapter.completed"; summary = "OpenCode fixture completed." } -14
    New-SkyBridgeEvent "demo-hermes-start-$stamp" "run.started" "info" "hermes" "hermes-api" `
      @{ session_id = "demo-hermes-session"; run_id = "demo-hermes-run" } `
      @{ title = "Hermes safe run"; health = "ok"; tunnel_status = "loopback"; capabilities = @("health", "capabilities", "safe-run-smoke") } -13
    New-SkyBridgeEvent "demo-hermes-degraded-$stamp" "agent.error" "warning" "hermes" "hermes-supervisor" `
      @{ session_id = "demo-hermes-session"; run_id = "demo-hermes-run" } `
      @{ summary = "Demo degraded state: cloud supervisor tunnel requires operator check."; api_health = "degraded"; tunnel_status = "loopback"; capabilities = @("health", "nightly-report") } -12
    New-SkyBridgeEvent "demo-automerge-sweep-$stamp" "iteration.state_changed" "info" "skybridge" "auto-merge-sweep" `
      @{ session_id = "demo-automerge-session"; run_id = "demo-automerge-sweep-run" } `
      @{ mode = "NightlySweep"; dry_run = $true; sweep_id = "demo-sweep-$stamp"; eligible = 1; blocked = 1; summary = "Dry-run found one eligible PR and one high-risk blocked PR." } -11
    New-SkyBridgeEvent "demo-ci-failed-$stamp" "iteration.ci_failed" "error" "skybridge" "ci-guardian" `
      @{ session_id = "demo-ci-session"; run_id = "demo-ci-run" } `
      @{ pr_number = 80; branch = "ai/high-risk-product-demo"; ci_state = "ci_failed"; required_checks = @(@{ name = "Project check"; status = "failed"; summary = "fixture failure" }); eligibility = "blocked"; risk = "blocked"; reasons = @("failed required check", "high-risk files need review") } -10
    New-SkyBridgeEvent "demo-notification-failed-$stamp" "notification.failed" "warning" "skybridge" "notification-center" `
      @{ session_id = "demo-notification-session"; run_id = "demo-notification-run" } `
      @{ provider = "gotify"; status = "failed"; reason = "provider not configured in demo" } -9
  )

  foreach ($event in $events) {
    Invoke-SkyBridgeJson "POST" "/v1/events" $event | Out-Null
  }

  $iterations = @(
    @{
      iteration_id = "demo-iter-green-$stamp"
      project_id = "skybridge-agent-hub"
      goal_id = "061-080"
      repo = "JerrySkywalker/skybridge-agent-hub"
      branch = "ai/productized-console-demo"
      base_branch = "main"
      state = "ci_green"
      pr_number = 79
      attempts = 1
      max_attempts = 3
      auto_merge_enabled = $false
      checks = @(
        @{ name = "Project check"; status = "passed"; summary = "demo green" },
        @{ name = "Docker build (server)"; status = "passed"; summary = "demo green" },
        @{ name = "Docker build (web)"; status = "passed"; summary = "demo green" }
      )
    }
    @{
      iteration_id = "demo-iter-blocked-$stamp"
      project_id = "skybridge-agent-hub"
      goal_id = "080"
      repo = "JerrySkywalker/skybridge-agent-hub"
      branch = "ai/high-risk-product-demo"
      base_branch = "main"
      state = "blocked"
      pr_number = 80
      attempts = 2
      max_attempts = 3
      auto_merge_enabled = $false
      last_error = "Blocked high-risk PR: workflow or deploy path changed."
      checks = @(
        @{ name = "Project check"; status = "failed"; summary = "fixture failure" },
        @{ name = "Docker build (web)"; status = "pending"; summary = "waiting" }
      )
    }
  )

  foreach ($iteration in $iterations) {
    Invoke-SkyBridgeJson "POST" "/v1/iterations" $iteration | Out-Null
    Invoke-SkyBridgeJson "POST" "/v1/iterations/$($iteration.iteration_id)/events" @{
      type = "iteration.state_changed"
      payload = @{
        state = $iteration.state
        pr_number = $iteration.pr_number
        reason = $iteration.last_error
      }
    } | Out-Null
  }

  $runs = Invoke-SkyBridgeJson "GET" "/v1/runs?limit=20"
  $eventList = Invoke-SkyBridgeJson "GET" "/v1/events?limit=50"
  $notifications = Invoke-SkyBridgeJson "GET" "/v1/notifications?limit=20"
  $prs = Invoke-SkyBridgeJson "GET" "/v1/prs/summary"

  [pscustomobject]@{
    ApiBase = $ApiBase
    Persistence = $health.persistence
    DbFile = $DbFile
    SeededEvents = $events.Count
    SeededIterations = $iterations.Count
    VisibleEvents = $eventList.events.Count
    Runs = $runs.runs.Count
    Notifications = $notifications.notifications.Count
    OpenPrs = $prs.open
    BlockedPrs = $prs.blocked
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
