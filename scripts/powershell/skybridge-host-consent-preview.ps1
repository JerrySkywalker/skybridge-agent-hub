[CmdletBinding()]
param(
  [ValidateSet("status", "consent-model", "consent-preview", "consent-gate", "explain-blocker", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\host-consent"

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  Set-Content -LiteralPath $Path -Value ($Lines -join "`n") -Encoding utf8
}

function New-ConsentModel {
  [pscustomobject]@{
    schema = "skybridge.host_mutation_consent_preview.v1"
    consent_states = @("disabled", "preview_requested", "blocked_by_default", "future_explicit_goal_required")
    current_state = "blocked_by_default"
    registry_write_allowed = $false
    startup_write_allowed = $false
    scheduled_task_allowed = $false
    service_install_allowed = $false
    path_mutation_allowed = $false
    powercfg_allowed = $false
    install_to_program_files_allowed = $false
    desktop_shortcut_allowed = $false
    start_menu_shortcut_allowed = $false
    token_printed = $false
  }
}

function New-ConsentGate {
  $model = New-ConsentModel
  [pscustomobject]@{
    schema = "skybridge.host_mutation_consent_gate.v1"
    gate = "blocked_by_default"
    host_mutation_allowed = $false
    consent_model = $model
    auth_can_enable_host_mutation = $false
    installer_interlock_required = $true
    future_explicit_goal_required = $true
    token_printed = $false
  }
}

function New-Report {
  $model = New-ConsentModel
  $gate = New-ConsentGate
  $report = [pscustomobject]@{
    schema = "skybridge.host_mutation_consent_report.v1"
    status = "ready"
    preview_only = $true
    consent_model = $model
    consent_gate = $gate
    host_mutation_performed = $false
    installer_real_mutation_allowed = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "host-consent-preview-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "host-consent-preview-report.md") @(
    "# Host Mutation Consent Preview Report",
    "",
    "- status: ready",
    "- preview_only: true",
    "- current_state: blocked_by_default",
    "- host_mutation_allowed: false",
    "- auth_can_enable_host_mutation: false",
    "- installer_real_mutation_allowed: false",
    "- future_explicit_goal_required: true",
    "- token_printed=false"
  )
  return $report
}

$Result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.host_mutation_consent_preview.v1"; status = "ready"; host_mutation_allowed = $false; token_printed = $false } }
  "consent-model" { New-ConsentModel }
  "consent-preview" { New-ConsentModel }
  "consent-gate" { New-ConsentGate }
  "explain-blocker" { [pscustomobject]@{ schema = "skybridge.host_mutation_blocker.v1"; blocker = "future_explicit_goal_required"; host_mutation_allowed = $false; token_printed = $false } }
  "safe-summary" { [pscustomobject]@{ ok = $true; host_mutation_allowed = $false; auth_can_enable_host_mutation = $false; token_printed = $false } }
  "report" { New-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 100 } else { $Result | Format-List | Out-String }
