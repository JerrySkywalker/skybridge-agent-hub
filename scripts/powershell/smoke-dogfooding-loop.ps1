param(
  [string]$ApiBase = "http://127.0.0.1:8787"
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

$health = Invoke-RestMethod "$ApiBase/v1/health"
if (-not $health.ok) { throw "SkyBridge health check failed" }

$runId = "dogfooding-$(Get-Date -Format yyyyMMddHHmmss)"
Send-Event (New-Event "run.started" $runId @{ title = "SkyBridge dogfooding loop"; lifecycle = "started" })
Send-Event (New-Event "tool.completed" $runId @{ tool_name = "codex-hook-smoke"; exit_code = 0 })
Send-Event (New-Event "notification.requested" $runId @{ title = "Dogfooding notification job"; body = "safe fixture" } "warning")
Send-Event (New-Event "run.completed" $runId @{ lifecycle = "completed" })

$run = Invoke-RestMethod "$ApiBase/v1/runs/$runId"
$notifications = Invoke-RestMethod "$ApiBase/v1/notifications?limit=20"

if ($run.summary.run_id -ne $runId) { throw "Run detail did not return dogfooding run" }

Write-Host "Dogfooding smoke passed for $runId"
Write-Host "Notifications observed: $($notifications.notifications.Count)"
