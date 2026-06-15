[CmdletBinding()]
param(
  [ValidateSet("status", "analyze-timeout", "cleanup-preview", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-launcher"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 20
  if (Test-UnsafeText $Text) { throw "Refusing unsafe stop-hook diagnostics JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe stop-hook diagnostics markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function New-TimeoutAnalysis {
  [pscustomobject]@{
    schema = "skybridge.stop_hook_diagnostics.v1"
    status = "timeout_analyzed"
    observed_message = "Stop hook failed: hook timed out after 30s"
    raw_hook_logs_read = $false
    raw_logs_persisted = $false
    kills_arbitrary_processes = $false
    host_mutation_required = $false
    likely_causes = @("long-running post-run hook", "slow cleanup", "stale child process", "blocked file handle", "network wait", "large report write", "unknown")
    next_safe_action = "Run cleanup-preview and inspect safe metadata reports under .agent/tmp only."
    cleanup_preview = New-CleanupPreview
    token_printed = $false
  }
}

function New-CleanupPreview {
  [pscustomobject]@{
    schema = "skybridge.stop_hook_cleanup_preview.v1"
    preview_only = $true
    removes_raw_logs = $false
    kills_arbitrary_processes = $false
    mutates_host_settings = $false
    safe_metadata_paths = @(".agent/tmp/local-launcher/stop-hook-diagnostics.json", ".agent/tmp/local-launcher/stop-hook-diagnostics.md")
    token_printed = $false
  }
}

function Write-Report {
  $Analysis = New-TimeoutAnalysis
  Write-SafeJson (Join-Path $ReportDir "stop-hook-diagnostics.json") $Analysis
  Write-SafeMarkdown (Join-Path $ReportDir "stop-hook-diagnostics.md") @(
    "# Stop Hook Diagnostics",
    "",
    "- schema: skybridge.stop_hook_diagnostics.v1",
    "- observed_message: Stop hook failed after bounded timeout",
    "- raw_hook_logs_read=false",
    "- raw_logs_persisted=false",
    "- kills_arbitrary_processes=false",
    "- host_mutation_required=false",
    "- token_printed=false"
  )
  $Analysis
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.stop_hook_diagnostics.v1"; status = "ready"; raw_logs_persisted = $false; host_mutation_required = $false; token_printed = $false } }
  "analyze-timeout" { New-TimeoutAnalysis }
  "cleanup-preview" { New-CleanupPreview }
  "safe-summary" { [pscustomobject]@{ ok = $true; raw_hook_logs_read = $false; raw_logs_persisted = $false; kills_arbitrary_processes = $false; host_mutation_required = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 20 } else { $Result | Format-List | Out-String }
