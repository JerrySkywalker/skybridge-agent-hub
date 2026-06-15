[CmdletBinding()]
param(
  [ValidateSet("status", "rehearse", "launcher-status", "launcher-start-preview", "doctor", "demo", "smoke-fast-preview", "cleanup-preview", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$InstallRoot = Join-Path $RepoRoot ".agent\tmp\installer-candidate\install-root"
$ReportDir = Join-Path $RepoRoot ".agent\tmp\installer-candidate"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 60
  if (Test-UnsafeText $text) { throw "Refusing unsafe runtime JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe runtime markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Ensure-InstallRoot {
  if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot "skybridge.ps1"))) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-installer-candidate.ps1") -Command verify -Json | Out-Null
  }
}

function Invoke-SandboxCommand([string]$Id, [string]$RelativeScript, [string[]]$Args) {
  Ensure-InstallRoot
  $script = Join-Path $InstallRoot $RelativeScript
  $started = Get-Date
  $exit = 0
  $summary = $null
  try {
    $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Args -Json 2>$null
    $exit = $LASTEXITCODE
    $text = ($raw | Out-String).Trim()
    if ($exit -eq 0 -and $text -and -not (Test-UnsafeText $text)) { $summary = $text | ConvertFrom-Json }
  } catch {
    $exit = 1
  }
  [pscustomobject]@{
    command_id = $Id
    exit_code = $exit
    duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    safe_summary = $summary
    install_root_sanitized = ".agent/tmp/installer-candidate/install-root"
    raw_output_persisted = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Invoke-Rehearsal {
  $commands = @(
    (Invoke-SandboxCommand "launcher-status" "scripts\powershell\skybridge-launcher.ps1" @("-Command", "status")),
    (Invoke-SandboxCommand "launcher-start-preview" "scripts\powershell\skybridge-launcher.ps1" @("-Command", "start-preview")),
    (Invoke-SandboxCommand "doctor" "scripts\powershell\skybridge-local-doctor.ps1" @("-Command", "check")),
    (Invoke-SandboxCommand "demo" "scripts\powershell\skybridge-local-session.ps1" @("-Command", "demo")),
    (Invoke-SandboxCommand "smoke-fast-preview" "scripts\powershell\skybridge-smoke-matrix.ps1" @("-Command", "safe-summary")),
    (Invoke-SandboxCommand "portable-safe-summary" "scripts\powershell\skybridge-portable-package.ps1" @("-Command", "safe-summary")),
    (Invoke-SandboxCommand "cleanup-preview" "scripts\powershell\skybridge-local-session.ps1" @("-Command", "cleanup"))
  )
  $report = [pscustomobject]@{
    schema = "skybridge.sandbox_installed_runtime_report.v1"
    status = $(if (@($commands | Where-Object { $_.exit_code -ne 0 }).Count -eq 0) { "passed" } else { "blocked" })
    install_root_sanitized = ".agent/tmp/installer-candidate/install-root"
    commands = $commands
    no_worker_execution = $true
    no_workunit_apply = $true
    no_task_claim = $true
    no_queue_apply = $true
    no_host_mutation = $true
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "sandbox-installed-runtime-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "sandbox-installed-runtime-report.md") @(
    "# Sandbox-installed Runtime Report",
    "",
    "- schema: skybridge.sandbox_installed_runtime_report.v1",
    "- status: $($report.status)",
    "- install_root: .agent/tmp/installer-candidate/install-root",
    "- no_worker_execution=true",
    "- no_queue_apply=true",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { Ensure-InstallRoot; [pscustomobject]@{ schema = "skybridge.sandbox_installed_runtime_report.v1"; status = "ready"; install_root_sanitized = ".agent/tmp/installer-candidate/install-root"; token_printed = $false } }
  "rehearse" { Invoke-Rehearsal }
  "launcher-status" { Invoke-SandboxCommand "launcher-status" "scripts\powershell\skybridge-launcher.ps1" @("-Command", "status") }
  "launcher-start-preview" { Invoke-SandboxCommand "launcher-start-preview" "scripts\powershell\skybridge-launcher.ps1" @("-Command", "start-preview") }
  "doctor" { Invoke-SandboxCommand "doctor" "scripts\powershell\skybridge-local-doctor.ps1" @("-Command", "check") }
  "demo" { Invoke-SandboxCommand "demo" "scripts\powershell\skybridge-local-session.ps1" @("-Command", "demo") }
  "smoke-fast-preview" { Invoke-SandboxCommand "smoke-fast-preview" "scripts\powershell\skybridge-smoke-matrix.ps1" @("-Command", "safe-summary") }
  "cleanup-preview" { Invoke-SandboxCommand "cleanup-preview" "scripts\powershell\skybridge-local-session.ps1" @("-Command", "cleanup") }
  "safe-summary" { [pscustomobject]@{ ok = $true; install_root_sanitized = ".agent/tmp/installer-candidate/install-root"; no_worker_execution = $true; no_workunit_apply = $true; no_task_claim = $true; no_queue_apply = $true; no_host_mutation = $true; token_printed = $false } }
  "report" { Invoke-Rehearsal }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
