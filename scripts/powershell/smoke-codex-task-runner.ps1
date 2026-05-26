[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = "Stop"

$runDir = Join-Path ".\.agent\tmp" ("codex-task-smoke-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$lastMessagePath = Join-Path $runDir "last-message.md"
$jsonlPath = Join-Path $runDir "codex-exec.jsonl"
$commandShapePath = Join-Path $runDir "dry-run-command.json"

$commandShape = @{
  command = "codex"
  args = @("exec", "--sandbox", "danger-full-access", "--json", "--output-last-message", $lastMessagePath, "<redacted-task-prompt>")
  log_path = $jsonlPath
  last_message_path = $lastMessagePath
  raw_logs_local_only = $true
  dry_run = [bool]$DryRun
}

$commandShape | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $commandShapePath -Encoding UTF8
$text = Get-Content -Raw -LiteralPath $commandShapePath
if ($text -cmatch "sk-(proj|ant|svcacct)-[A-Za-z0-9_-]+" -or $text -match "(?i)authorization:\s*bearer|password\s*[:=]\s*[^,\s}]+|cookie\s*[:=]\s*[^,\s}]+") {
  throw "Dry-run command shape exposed a secret-like value."
}
if (-not (Test-Path -LiteralPath $runDir -PathType Container)) { throw "Expected dry-run log directory." }

if (-not $DryRun) {
  throw "Real Codex smoke execution is intentionally not enabled by default. Re-run with -DryRun."
}

[pscustomobject]@{
  DryRun = $true
  CommandShapePath = (Resolve-Path -LiteralPath $commandShapePath).Path
  LogPath = $jsonlPath
  LastMessagePath = $lastMessagePath
  SecretsPrinted = $false
  CodexExecuted = $false
} | Format-List
