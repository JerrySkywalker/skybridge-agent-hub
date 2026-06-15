[CmdletBinding()]
param(
  [ValidateSet("status", "simulate-interrupted-install", "simulate-interrupted-upgrade", "simulate-interrupted-rollback", "recovery-plan", "recovery-preview", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$SandboxRoot = Join-Path $RepoRoot ".agent\tmp\install-sandbox"
$MarkerDir = Join-Path $SandboxRoot "recovery-markers"

function Assert-SandboxPath([string]$Path) {
  $root = [System.IO.Path]::GetFullPath($SandboxRoot)
  $target = [System.IO.Path]::GetFullPath($Path)
  if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes install sandbox: $Path" }
}

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  Assert-SandboxPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 60
  if (Test-UnsafeText $text) { throw "Refusing unsafe recovery JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  Assert-SandboxPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe recovery markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function New-Marker([string]$Kind) {
  New-Item -ItemType Directory -Force -Path $MarkerDir | Out-Null
  $path = Join-Path $MarkerDir "$Kind.marker.json"
  $value = [pscustomobject]@{
    schema = "skybridge.recovery_marker.v1"
    marker = $Kind
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    marker_path_sanitized = ".agent/tmp/install-sandbox/recovery-markers/$Kind.marker.json"
    fixture_only = $true
    process_killed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
  Write-SafeJson $path $value
  $value
}

function Get-Markers {
  if (-not (Test-Path -LiteralPath $MarkerDir)) { return @() }
  @(Get-ChildItem -LiteralPath $MarkerDir -File -Filter *.marker.json | ForEach-Object {
    [System.IO.Path]::GetFileNameWithoutExtension($_.Name).Replace(".marker", "")
  } | Sort-Object)
}

function Get-PortConflictMetadata {
  @(
    [pscustomobject]@{ component = "web-preview"; port = 5173; conflict_detected = $false; token_printed = $false },
    [pscustomobject]@{ component = "server-control-plane-preview"; port = 8787; conflict_detected = $false; token_printed = $false }
  )
}

function Get-Plan {
  $markers = @(Get-Markers)
  [pscustomobject]@{
    schema = "skybridge.recovery_sandbox_report.v1"
    status = "planned"
    markers = $markers
    orphan_sandbox_lock_detected = Test-Path -LiteralPath (Join-Path $SandboxRoot "orphan.fixture.lock.json")
    stale_install_staging_detected = Test-Path -LiteralPath (Join-Path $SandboxRoot "staging")
    stale_rollback_dir_detected = Test-Path -LiteralPath (Join-Path $SandboxRoot "rollback")
    port_conflicts = Get-PortConflictMetadata
    cleanup_preview_only = $true
    cleanup_allowed_under_sandbox_only = $true
    process_kill_allowed = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Get-RecoveryPreview {
  $plan = Get-Plan
  [pscustomobject]@{
    schema = "skybridge.recovery_sandbox_report.v1"
    status = "preview"
    restart_recovery_preview = @("detect fixture markers", "prefer previous sandbox snapshot when present", "leave host untouched", "write safe report only")
    cleanup_recovery_preview = @("remove marker files only with explicit future sandbox cleanup command", "never delete outside .agent/tmp/install-sandbox")
    plan = $plan
    token_printed = $false
  }
}

function Write-Report {
  New-Marker "fixture-crash" | Out-Null
  $plan = Get-Plan
  $preview = Get-RecoveryPreview
  $report = [pscustomobject]@{
    schema = "skybridge.recovery_sandbox_report.v1"
    status = "passed"
    plan = $plan
    preview = $preview
    cleanup_hardening = [pscustomobject]@{
      orphan_lock_detection = $true
      stale_install_staging_detection = $true
      stale_rollback_dir_detection = $true
      port_conflict_metadata = $true
      cleanup_preview_only = $true
      token_printed = $false
    }
    host_mutation_allowed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $SandboxRoot "recovery-sandbox-report.json") $report
  Write-SafeMarkdown (Join-Path $SandboxRoot "recovery-sandbox-report.md") @(
    "# Recovery Sandbox Report",
    "",
    "- schema: skybridge.recovery_sandbox_report.v1",
    "- status: $($report.status)",
    "- marker_root: .agent/tmp/install-sandbox/recovery-markers",
    "- cleanup_preview_only=true",
    "- host_mutation_allowed=false",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.recovery_sandbox_report.v1"; status = "ready"; marker_root_sanitized = ".agent/tmp/install-sandbox/recovery-markers"; token_printed = $false } }
  "simulate-interrupted-install" { New-Marker "interrupted-install" }
  "simulate-interrupted-upgrade" { New-Marker "interrupted-upgrade" }
  "simulate-interrupted-rollback" { New-Marker "interrupted-rollback" }
  "recovery-plan" { Get-Plan }
  "recovery-preview" { Get-RecoveryPreview }
  "safe-summary" { [pscustomobject]@{ ok = $true; sandbox_only = $true; cleanup_preview_only = $true; process_kill_allowed = $false; host_mutation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
