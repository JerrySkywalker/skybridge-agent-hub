param(
  [string]$ApiBase = $env:SKYBRIDGE_API_BASE,
  [string]$SpoolDirectory = $env:SKYBRIDGE_CODEX_SPOOL_DIR,
  [int]$TimeoutSeconds = 3,
  [int]$MaxQueueLines = 1000
)

# Read Codex hook JSON from stdin, normalize to skybridge.agent_event.v1, and deliver fail-open.
$ErrorActionPreference = "Stop"

function Get-RepositoryRoot {
  $current = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
  while ($true) {
    if (Test-Path (Join-Path $current "pnpm-workspace.yaml")) { return $current }
    $parent = Split-Path -Parent $current
    if ($parent -eq $current) { return (Get-Location).Path }
    $current = $parent
  }
}

function Get-SpoolDirectory {
  param([string]$Requested)
  if (-not [string]::IsNullOrWhiteSpace($Requested)) { return $Requested }
  return (Join-Path (Get-RepositoryRoot) ".agent\spool\codex-hook")
}

function Get-SharedRedactionRules {
  $fallback = @{
    replacement = "[REDACTED]"
    maxStringLength = 2000
    secretKeyPatterns = @("token", "password", "passwd", "authorization", "cookie", "secret", "api[_-]?key", "private[_-]?key")
    secretValuePatterns = @("Bearer\s+[A-Za-z0-9._-]+", "sk-[A-Za-z0-9_-]{12,}", "-----BEGIN [A-Z ]*PRIVATE KEY-----", "-----BEGIN OPENSSH PRIVATE KEY-----")
    omitKeyPatterns = @("prompt", "patch", "stdout", "stderr", "command_output", "raw_output", "tool_result")
    source = "fallback"
  }

  try {
    $rulesPath = Join-Path (Get-RepositoryRoot) "packages\event-schema\src\redaction-rules.json"
    if (-not (Test-Path $rulesPath)) { return $fallback }
    $rules = Get-Content -Raw -Path $rulesPath | ConvertFrom-Json -AsHashtable
    $rules["source"] = "packages/event-schema/src/redaction-rules.json"
    return $rules
  } catch {
    return $fallback
  }
}

$SharedRedactionRules = Get-SharedRedactionRules

function Test-SharedRedactionPattern {
  param([AllowNull()][string]$Value, [AllowNull()]$Patterns)
  if ([string]::IsNullOrWhiteSpace($Value) -or $null -eq $Patterns) { return $false }
  foreach ($pattern in @($Patterns)) {
    if ($Value -match "(?i)$pattern") { return $true }
  }
  return $false
}

function Redact-String {
  param([AllowNull()][string]$Value, [int]$MaxLength = 160)
  if ($null -eq $Value) { return $null }
  $text = $Value
  foreach ($pattern in @($SharedRedactionRules.secretValuePatterns)) {
    $text = [regex]::Replace($text, $pattern, [string]$SharedRedactionRules.replacement, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  }
  $text = $text -replace '(?i)\b([A-Za-z0-9_.-]*(token|password|passwd|secret|api[_-]?key)[A-Za-z0-9_.-]*)\s*[:=]\s*([^\s;&|]+)', "`$1=$($SharedRedactionRules.replacement)"
  if ($text.Length -gt $MaxLength) { return "$($text.Substring(0, $MaxLength))...[truncated $($text.Length - $MaxLength) chars]" }
  return $text
}

function ConvertTo-SafeValue {
  param($Value, [int]$Depth = 0)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) { return (Redact-String -Value $Value) }
  if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return $Value }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [hashtable] -and $Value -isnot [string]) {
    if ($Depth -ge 4) { return @{ bounded = $true; type = "array" } }
    return @($Value | Select-Object -First 24 | ForEach-Object { ConvertTo-SafeValue -Value $_ -Depth ($Depth + 1) })
  }
  if ($Value -is [hashtable]) {
    if ($Depth -ge 4) { return @{ bounded = $true; type = "object"; keys = @($Value.Keys | Select-Object -First 24) } }
    $result = @{}
    foreach ($key in @($Value.Keys | Select-Object -First 24)) {
      if (Test-SharedRedactionPattern -Value ([string]$key) -Patterns $SharedRedactionRules.secretKeyPatterns) {
        $result[$key] = $SharedRedactionRules.replacement
      } elseif ((Test-SharedRedactionPattern -Value ([string]$key) -Patterns $SharedRedactionRules.omitKeyPatterns) -or [string]$key -match '(?i)command|output|content') {
        $item = $Value[$key]
        $result[$key] = @{ bounded = $true; type = if ($null -eq $item) { "null" } else { $item.GetType().Name }; length = if ($item -is [string]) { $item.Length } else { $null } }
      } else {
        $result[$key] = ConvertTo-SafeValue -Value $Value[$key] -Depth ($Depth + 1)
      }
    }
    if ($Value.Keys.Count -gt 24) { $result["__truncated_keys"] = $Value.Keys.Count - 24 }
    return $result
  }
  return (Redact-String -Value ([string]$Value))
}

function Get-String {
  param($Value)
  if ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)) { return $Value }
  return $null
}

function Get-ToolName {
  param([hashtable]$Event)
  if ($Event["tool_input"] -is [hashtable] -and $Event["tool_input"].ContainsKey("name")) { return (Get-String $Event["tool_input"]["name"]) }
  $name = Get-String $Event["tool_name"]
  if ($name) { return $name }
  return (Get-String $Event["tool"])
}

function Get-OutputSummary {
  param($Text)
  $value = Get-String $Text
  if (-not $value) { return $null }
  return @{
    present = $true
    length = $value.Length
    line_count = @($value -split "`r?`n").Count
    preview = Redact-String -Value $value -MaxLength 120
  }
}

function Get-ToolInputSummary {
  param($ToolInput)
  if ($ToolInput -isnot [hashtable]) { return $null }
  $command = Get-String $ToolInput["command"]
  $filePath = Get-String $ToolInput["file_path"]
  if (-not $filePath) { $filePath = Get-String $ToolInput["path"] }
  $content = Get-String $ToolInput["content"]
  if (-not $content) { $content = Get-String $ToolInput["patch"] }
  return @{
    name = Get-String $ToolInput["name"]
    command_present = -not [string]::IsNullOrWhiteSpace($command)
    command_length = if ($command) { $command.Length } else { $null }
    command_preview = if ($command) { Redact-String -Value $command -MaxLength 120 } else { $null }
    file_path = if ($filePath) { Redact-String -Value $filePath -MaxLength 160 } else { $null }
    content_present = -not [string]::IsNullOrWhiteSpace($content)
    content_length = if ($content) { $content.Length } else { $null }
    keys = @($ToolInput.Keys | Sort-Object | Select-Object -First 24)
    bounded_payload = ConvertTo-SafeValue -Value $ToolInput
  }
}

function New-SkyBridgeEvents {
  param([hashtable]$InputObject)
  $hookEventName = Get-String $InputObject["hook_event_name"]
  if (-not $hookEventName) { $hookEventName = Get-String $InputObject["event"] }
  if (-not $hookEventName) { $hookEventName = "Unknown" }

  $exitCode = $InputObject["exit_code"]
  if ($null -eq $exitCode -and $InputObject["tool_response"] -is [hashtable]) { $exitCode = $InputObject["tool_response"]["exit_code"] }
  $failedTool = $hookEventName -eq "PostToolUse" -and $null -ne $exitCode -and [int]$exitCode -ne 0
  $eventType = switch ($hookEventName) {
    "SessionStart" { "session.started" }
    "UserPromptSubmit" { "run.started" }
    "PreToolUse" { "tool.started" }
    "PostToolUse" { if ($failedTool) { "tool.failed" } else { "tool.completed" } }
    "PermissionRequest" { "approval.requested" }
    "Stop" { "turn.completed" }
    default { "agent.idle" }
  }

  $runId = Get-String $InputObject["run_id"]
  if (-not $runId) { $runId = Get-String $InputObject["conversation_id"] }
  if (-not $runId) { $runId = Get-String $InputObject["session_id"] }

  $toolResponse = if ($InputObject["tool_response"] -is [hashtable]) { $InputObject["tool_response"] } else { @{} }
  $source = @{
    platform = "codex"
    adapter = "codex-hook"
    node_id = $env:SKYBRIDGE_NODE_ID
    agent_id = "codex-cli"
    cwd = Get-String $InputObject["cwd"]
  }
  $correlation = @{
    session_id = Get-String $InputObject["session_id"]
    run_id = $runId
    turn_id = if (Get-String $InputObject["turn_id"]) { Get-String $InputObject["turn_id"] } else { Get-String $InputObject["request_id"] }
    tool_call_id = if (Get-String $InputObject["tool_use_id"]) { Get-String $InputObject["tool_use_id"] } else { Get-String $InputObject["tool_call_id"] }
  }
  $event = @{
    schema = "skybridge.agent_event.v1"
    time = (Get-Date).ToUniversalTime().ToString("o")
    type = $eventType
    severity = if ($eventType -eq "approval.requested") { "warning" } elseif ($eventType -eq "tool.failed") { "error" } else { "info" }
    source = $source
    correlation = $correlation
    payload = @{
      hook_event_name = $hookEventName
      session_start_type = if (Get-String $InputObject["session_start_type"]) { Get-String $InputObject["session_start_type"] } else { Get-String $InputObject["source"] }
      tool_name = Get-ToolName -Event $InputObject
      permission_mode = Get-String $InputObject["permission_mode"]
      exit_code = $exitCode
      stdout_summary = if ($InputObject.ContainsKey("stdout")) { Get-OutputSummary $InputObject["stdout"] } else { Get-OutputSummary $toolResponse["stdout"] }
      stderr_summary = if ($InputObject.ContainsKey("stderr")) { Get-OutputSummary $InputObject["stderr"] } else { Get-OutputSummary $toolResponse["stderr"] }
      tool_input_summary = Get-ToolInputSummary $InputObject["tool_input"]
      message_summary = if ($InputObject.ContainsKey("prompt")) { Get-OutputSummary $InputObject["prompt"] } else { Get-OutputSummary $InputObject["message"] }
      redaction = "commands, prompts, stdout and stderr are redacted and bounded by default"
      redaction_policy = @{
        source = $SharedRedactionRules.source
        max_string_length = $SharedRedactionRules.maxStringLength
      }
    }
  }
  $events = @($event)
  if ((Get-ToolName -Event $InputObject) -eq "apply_patch") {
    $path = $null
    if ($InputObject["tool_input"] -is [hashtable]) {
      $path = if (Get-String $InputObject["tool_input"]["file_path"]) { Get-String $InputObject["tool_input"]["file_path"] } else { Get-String $InputObject["tool_input"]["path"] }
    }
    $events += @{
      schema = "skybridge.agent_event.v1"; time = (Get-Date).ToUniversalTime().ToString("o"); type = "file.edited"; severity = "info"; source = $source; correlation = $correlation
      payload = @{ hook_event_name = $hookEventName; file_path = $path; redaction = "patch content omitted by default" }
    }
    $events += @{
      schema = "skybridge.agent_event.v1"; time = (Get-Date).ToUniversalTime().ToString("o"); type = "diff.updated"; severity = "info"; source = $source; correlation = $correlation
      payload = @{ hook_event_name = $hookEventName; file_path = $path; diff_present = $true; redaction = "diff content omitted by default" }
    }
  }
  return $events
}

function Write-JsonLine {
  param([string]$Path, [string]$Line)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  Add-Content -Path $Path -Value $Line -Encoding UTF8
}

function Limit-JsonLines {
  param([string]$Path, [int]$MaxLines)
  if (-not (Test-Path $Path)) { return }
  $lines = @(Get-Content -Path $Path -ErrorAction SilentlyContinue)
  if ($lines.Count -le $MaxLines) { return }
  $lines | Select-Object -Last $MaxLines | Set-Content -Path $Path -Encoding UTF8
}

function Remove-NullValues {
  param($Value)
  if ($Value -is [hashtable]) {
    $output = @{}
    foreach ($key in $Value.Keys) {
      $clean = Remove-NullValues -Value $Value[$key]
      if ($null -ne $clean) { $output[$key] = $clean }
    }
    return $output
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    return ,@($Value | ForEach-Object { Remove-NullValues -Value $_ } | Where-Object { $null -ne $_ })
  }
  return $Value
}

try {
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { $ApiBase = "http://127.0.0.1:8787" }
  $spoolDir = Get-SpoolDirectory -Requested $SpoolDirectory
  $queueFile = Join-Path $spoolDir "queue.jsonl"
  $auditFile = Join-Path $spoolDir "events.jsonl"

  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
  $inputObj = $raw | ConvertFrom-Json -AsHashtable
  $events = @(New-SkyBridgeEvents -InputObject $inputObj)

  foreach ($event in $events) {
    $body = (Remove-NullValues -Value $event) | ConvertTo-Json -Depth 80 -Compress
    Write-JsonLine -Path $auditFile -Line $body
    $headers = @{}
    if ($env:CODEX_DASHBOARD_TOKEN) { $headers["Authorization"] = "Bearer $($env:CODEX_DASHBOARD_TOKEN)" }
    try {
      Invoke-RestMethod -Method Post -Uri "$ApiBase/v1/events" -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec $TimeoutSeconds | Out-Null
    } catch {
      Write-JsonLine -Path $queueFile -Line $body
    }
  }
  Limit-JsonLines -Path $auditFile -MaxLines $MaxQueueLines
  Limit-JsonLines -Path $queueFile -MaxLines $MaxQueueLines
} catch {
  # Hooks must never break Codex execution.
}

exit 0
