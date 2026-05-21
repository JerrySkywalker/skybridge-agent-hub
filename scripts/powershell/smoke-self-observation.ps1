param(
  [string]$ApiBase = "http://127.0.0.1:8787",
  [string]$RunId = "",
  [string]$SessionId = "",
  [switch]$IncludeFailure,
  [int]$TimeoutSeconds = 5
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RunId)) {
  $RunId = "smoke-self-observation-$((Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss"))"
}

if ([string]::IsNullOrWhiteSpace($SessionId)) {
  $SessionId = "smoke-session-$PID"
}

$api = $ApiBase.TrimEnd("/")

function New-SmokeEvent {
  param(
    [Parameter(Mandatory=$true)][string]$Type,
    [ValidateSet("debug", "info", "warning", "error", "critical")]
    [string]$Severity = "info",
    [hashtable]$Payload = @{},
    [string]$ToolCallId = $null
  )

  $correlation = @{
    session_id = $SessionId
    run_id = $RunId
  }
  if (-not [string]::IsNullOrWhiteSpace($ToolCallId)) {
    $correlation.tool_call_id = $ToolCallId
  }

  return @{
    schema = "skybridge.agent_event.v1"
    event_id = "evt_smoke_$([Guid]::NewGuid().ToString("N"))"
    time = (Get-Date).ToUniversalTime().ToString("o")
    type = $Type
    severity = $Severity
    source = @{
      platform = "skybridge"
      adapter = "self-observation-smoke"
      agent_id = "local-smoke"
      node_id = $env:COMPUTERNAME
      cwd = (Get-Location).Path
    }
    correlation = $correlation
    payload = $Payload
  }
}

function Send-SmokeEvent {
  param([Parameter(Mandatory=$true)][hashtable]$Event)

  $body = $Event | ConvertTo-Json -Depth 40 -Compress
  Invoke-RestMethod `
    -Method Post `
    -Uri "$api/v1/events" `
    -ContentType "application/json" `
    -Body $body `
    -TimeoutSec $TimeoutSeconds | Out-Null
}

Write-Host "[skybridge-smoke] target: $api"
Write-Host "[skybridge-smoke] run: $RunId"

$events = @(
  (New-SmokeEvent -Type "run.started" -Payload @{
    title = "Self-observation smoke"
    lifecycle = "smoke.run.started"
    goalId = "mega-001"
    goalFile = "001-self-observable-skybridge-loop.md"
    branch = (git branch --show-current 2>$null)
    redaction = "smoke payload omits command output and secrets"
  }),
  (New-SmokeEvent -Type "tool.started" -ToolCallId "smoke-ingest" -Payload @{
    lifecycle = "smoke.tool.started"
    tool_name = "Invoke-RestMethod"
    command = "POST /v1/events"
    output_omitted = $true
    redaction = "HTTP response bodies omitted by default"
  }),
  (New-SmokeEvent -Type "tool.completed" -ToolCallId "smoke-ingest" -Payload @{
    lifecycle = "smoke.tool.completed"
    tool_name = "Invoke-RestMethod"
    exitCode = 0
    output_omitted = $true
    redaction = "HTTP response bodies omitted by default"
  }),
  (New-SmokeEvent -Type "notification.requested" -Severity "warning" -Payload @{
    lifecycle = "smoke.notification.requested"
    title = "SkyBridge smoke notification"
    priority = "default"
    message_length = 38
    message_omitted = $true
    redaction = "notification body omitted by default"
  })
)

if ($IncludeFailure) {
  $events += New-SmokeEvent -Type "tool.failed" -Severity "warning" -ToolCallId "smoke-failure" -Payload @{
    lifecycle = "smoke.tool.failed"
    tool_name = "simulated-check"
    exitCode = 1
    output_omitted = $true
    redaction = "simulated failure output omitted by default"
  }
  $events += New-SmokeEvent -Type "run.failed" -Severity "error" -Payload @{
    lifecycle = "smoke.run.failed"
    error_summary = "Simulated smoke failure requested with -IncludeFailure."
    logs_omitted = $true
    redaction = "failure logs omitted by default"
  }
} else {
  $events += New-SmokeEvent -Type "run.completed" -Payload @{
    lifecycle = "smoke.run.completed"
    checksPassed = $true
  }
}

foreach ($event in $events) {
  Send-SmokeEvent -Event $event
}

$escapedRunId = [Uri]::EscapeDataString($RunId)
$run = Invoke-RestMethod -Method Get -Uri "$api/v1/runs/$escapedRunId" -TimeoutSec $TimeoutSeconds
$scopedEvents = Invoke-RestMethod -Method Get -Uri "$api/v1/events?run_id=$escapedRunId" -TimeoutSec $TimeoutSeconds
$notifications = Invoke-RestMethod -Method Get -Uri "$api/v1/notifications" -TimeoutSec $TimeoutSeconds

if ($run.summary.run_id -ne $RunId) {
  throw "Run detail did not return the expected run id."
}

if ($scopedEvents.events.Count -lt $events.Count) {
  throw "Scoped event query returned fewer events than the smoke script sent."
}

Write-Host "[skybridge-smoke] status: $($run.summary.status)"
Write-Host "[skybridge-smoke] events: $($scopedEvents.events.Count)"
Write-Host "[skybridge-smoke] tools: $($run.summary.tool_call_count), notifications: $($run.summary.notification_count)"
Write-Host "[skybridge-smoke] stored notifications: $($notifications.notifications.Count)"
