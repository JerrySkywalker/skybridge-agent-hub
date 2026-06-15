[CmdletBinding()]
param(
  [ValidateSet("status", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\installer-candidate"
$RcVersion = "v1.8.0-sandboxed-installer-soak-rc"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 60
  if (Test-UnsafeText $text) { throw "Refusing unsafe RC report JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe RC report markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$Args) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @Args -Json 2>$null
  if ($LASTEXITCODE -ne 0) { throw "$Script failed" }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "$Script emitted unsafe text" }
  $text | ConvertFrom-Json
}

function Get-StatusValue($Value, [string]$Field = "status") {
  if ($null -eq $Value) { return "not_reported" }
  $prop = $Value.PSObject.Properties[$Field]
  if ($prop) { return [string]$prop.Value }
  "not_reported"
}

function Write-RcReport {
  $releaseGuard = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "report")
  $installer = Invoke-JsonScript "skybridge-installer-candidate.ps1" @("-Command", "report")
  $runtime = Invoke-JsonScript "skybridge-sandbox-installed-runtime.ps1" @("-Command", "report")
  $soak = Invoke-JsonScript "skybridge-install-soak.ps1" @("-Command", "report")
  $recovery = Invoke-JsonScript "skybridge-recovery-sandbox.ps1" @("-Command", "report")
  $operator = Invoke-JsonScript "skybridge-operator-acceptance.ps1" @("-Command", "v3-report")
  $report = [pscustomobject]@{
    schema = "skybridge.installer_soak_rc_report.v1"
    rc_version = $RcVersion
    commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    release_workflow_guard_status = $(if ($releaseGuard.gate) { $releaseGuard.gate.gate } else { Get-StatusValue $releaseGuard })
    installer_candidate_status = Get-StatusValue $installer
    sandbox_installed_runtime_status = Get-StatusValue $runtime
    install_soak_status = Get-StatusValue $soak
    recovery_status = Get-StatusValue $recovery
    operator_acceptance_v3_status = Get-StatusValue $operator
    disabled_capabilities = @("codex_worker", "workunit_creation", "workunit_apply", "task_creation", "task_claim", "task_pr_creation", "generic_queue_apply", "start_all", "start_queue", "resume_apply", "remote_execution", "arbitrary_command_dispatch", "host_install", "host_uninstall", "registry", "startup", "scheduled_task", "service", "powercfg", "PATH", "manual_upload", "manual_github_release")
    known_limitations = @("sandbox-only installer candidate", "unsigned archive", "no host install", "no network update", "tag may trigger existing release/docker workflows")
    next_recommended_goals = @("signed archive planning", "host installer design review", "installer visual QA", "release workflow artifact retention review")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "installer-soak-rc-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "installer-soak-rc-report.md") @(
    "# Installer Soak RC Report",
    "",
    "- schema: skybridge.installer_soak_rc_report.v1",
    "- rc_version: $RcVersion",
    "- release_workflow_guard_status: $($report.release_workflow_guard_status)",
    "- installer_candidate_status: $($report.installer_candidate_status)",
    "- sandbox_installed_runtime_status: $($report.sandbox_installed_runtime_status)",
    "- install_soak_status: $($report.install_soak_status)",
    "- recovery_status: $($report.recovery_status)",
    "- operator_acceptance_v3_status: $($report.operator_acceptance_v3_status)",
    "- token_printed=false"
  )
  $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.installer_soak_rc_report.v1"; status = "ready"; rc_version = $RcVersion; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; rc_version = $RcVersion; host_mutation_allowed = $false; manual_upload_allowed = $false; manual_github_release_allowed = $false; token_printed = $false } }
  "report" { Write-RcReport }
}

if ($Json) { $Result | ConvertTo-Json -Depth 70 } else { $Result | Format-List | Out-String }
