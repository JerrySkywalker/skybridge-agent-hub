# Read Codex hook JSON from stdin, normalize minimally, and POST to SkyBridge.
$ErrorActionPreference = "Stop"

try {
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

  $inputObj = $raw | ConvertFrom-Json -AsHashtable
  $hookEventName = [string]$inputObj["hook_event_name"]
  $eventType = switch ($hookEventName) {
    "SessionStart" { "session.started" }
    "UserPromptSubmit" { "run.started" }
    "PreToolUse" { "tool.started" }
    "PostToolUse" { "tool.completed" }
    "PermissionRequest" { "approval.requested" }
    "Stop" { "turn.completed" }
    default { "agent.idle" }
  }

  $toolInput = $inputObj["tool_input"]
  $toolSummary = @{}
  if ($toolInput -is [hashtable]) {
    $command = [string]$toolInput["command"]
    $toolSummary = @{
      keys = @($toolInput.Keys | Sort-Object)
      command_present = -not [string]::IsNullOrWhiteSpace($command)
      command_length = if ([string]::IsNullOrWhiteSpace($command)) { 0 } else { $command.Length }
      file_path = $toolInput["file_path"] ?? $toolInput["path"]
    }
  }

  $runId = $inputObj["run_id"]
  if ([string]::IsNullOrWhiteSpace([string]$runId)) { $runId = $inputObj["conversation_id"] }
  if ([string]::IsNullOrWhiteSpace([string]$runId)) { $runId = $inputObj["session_id"] }

  $payload = @{
    schema = "skybridge.agent_event.v1"
    time = (Get-Date).ToUniversalTime().ToString("o")
    type = $eventType
    severity = "info"
    source = @{
      platform = "codex"
      adapter = "codex-hook"
      node_id = $env:SKYBRIDGE_NODE_ID
      agent_id = "codex-cli"
      cwd = $inputObj["cwd"]
    }
    correlation = @{
      session_id = $inputObj["session_id"]
      run_id = $runId
      turn_id = $inputObj["turn_id"] ?? $inputObj["request_id"]
      tool_call_id = $inputObj["tool_use_id"] ?? $inputObj["tool_call_id"]
    }
    payload = @{
      hook_event_name = $hookEventName
      tool_name = $inputObj["tool_name"] ?? $inputObj["tool"]
      permission_mode = $inputObj["permission_mode"]
      tool_input_summary = $toolSummary
      redaction = "command/stdout/stderr omitted by default"
    }
  }

  $body = $payload | ConvertTo-Json -Depth 80 -Compress

  $dir = Join-Path $env:USERPROFILE ".codex\dashboard"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Add-Content -Path (Join-Path $dir "events.jsonl") -Value $body -Encoding UTF8

  $api = $env:SKYBRIDGE_API_BASE
  if ([string]::IsNullOrWhiteSpace($api)) { $api = "http://127.0.0.1:8787" }

  $headers = @{}
  if ($env:CODEX_DASHBOARD_TOKEN) {
    $headers["Authorization"] = "Bearer $($env:CODEX_DASHBOARD_TOKEN)"
  }

  try {
    Invoke-RestMethod -Method Post -Uri "$api/v1/events" -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec 3 | Out-Null
  } catch {
    # fail open
  }
} catch {
  # fail open
}

exit 0
