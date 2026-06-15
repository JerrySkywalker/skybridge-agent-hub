[CmdletBinding()]
param(
  [ValidateSet("status", "gate", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\release-candidate"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 60
  if (Test-UnsafeText $text) { throw "Refusing unsafe installer safety interlock JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function New-Interlock {
  [pscustomobject]@{
    schema = "skybridge.installer_safety_interlock.v1"
    status = "blocked_for_host_mutation"
    safe_preview_allowed = $true
    real_install_allowed = $false
    registry_write_allowed = $false
    startup_write_allowed = $false
    scheduled_task_allowed = $false
    service_install_allowed = $false
    path_mutation_allowed = $false
    powercfg_allowed = $false
    program_files_write_allowed = $false
    appdata_write_allowed = $false
    network_update_allowed = $false
    manual_github_release_creation_allowed = $false
    manual_upload_allowed = $false
    blocks_token_printed_true = $true
    called_by = @("installer candidate", "install sandbox", "release artifact promotion", "manual install preview", "update channel preview")
    token_printed = $false
  }
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.installer_safety_interlock.v1"; status = "ready"; token_printed = $false } }
  "gate" { $r = New-Interlock; Write-SafeJson (Join-Path $ReportDir "installer-safety-interlock.json") $r; $r }
  "safe-summary" { [pscustomobject]@{ ok = $true; safe_preview_allowed = $true; real_install_allowed = $false; network_update_allowed = $false; manual_upload_allowed = $false; token_printed = $false } }
  "report" { $r = New-Interlock; Write-SafeJson (Join-Path $ReportDir "installer-safety-interlock.json") $r; $r }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
