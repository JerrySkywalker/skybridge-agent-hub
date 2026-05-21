param(
  [string]$OutputPath = ".\docs\demo\skybridge-demo-events.json"
)

$ErrorActionPreference = "Stop"

function New-Event {
  param(
    [string]$Type,
    [string]$Platform,
    [string]$Adapter,
    [string]$RunId,
    [hashtable]$Payload = @{},
    [string]$Severity = "info"
  )

  @{
    schema = "skybridge.agent_event.v1"
    time = (Get-Date).ToUniversalTime().ToString("o")
    type = $Type
    severity = $Severity
    source = @{ platform = $Platform; adapter = $Adapter }
    correlation = @{ run_id = $RunId; session_id = "$RunId-session" }
    payload = $Payload
  }
}

$events = @(
  New-Event "run.started" "codex" "codex-hook" "demo-codex" @{ title = "Codex demo run"; category = "dogfooding" }
  New-Event "tool.completed" "codex" "codex-hook" "demo-codex" @{ tool_name = "shell"; output_omitted = $true }
  New-Event "run.completed" "opencode" "opencode-plugin" "demo-opencode" @{ title = "OpenCode demo run" }
  New-Event "run.failed" "hermes" "hermes-api" "demo-hermes-failed" @{ title = "Hermes failed run"; detail = "fixture failure" } "error"
  New-Event "approval.requested" "codex" "codex-hook" "demo-approval" @{ approval_id = "demo-approval-1"; title = "Approve safe fixture action" } "warning"
  New-Event "notification.sent" "skybridge" "demo-dataset" "demo-notify-sent" @{ provider = "ntfy"; status = "sent" }
  New-Event "notification.skipped" "skybridge" "demo-dataset" "demo-notify-skipped" @{ provider = "placeholder"; status = "skipped" }
  New-Event "notification.failed" "skybridge" "demo-dataset" "demo-notify-failed" @{ provider = "gotify"; status = "failed" } "warning"
  New-Event "node.heartbeat" "skybridge" "sidecar" "demo-node" @{ node_id = "demo-node"; host = "demo"; labels = @("local", "demo"); capabilities = @("event-forwarding", "heartbeat") }
  New-Event "agent.stale" "skybridge" "yolo-runner" "demo-runner" @{ title = "Runner stale fixture" } "warning"
)

$directory = Split-Path -Parent $OutputPath
if ($directory) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$events | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding utf8
Write-Host "Wrote $($events.Count) demo events to $OutputPath"
