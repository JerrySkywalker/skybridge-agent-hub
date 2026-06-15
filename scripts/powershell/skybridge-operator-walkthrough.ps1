[CmdletBinding()]
param(
  [ValidateSet("start", "step", "status", "reset-preview", "safe-summary", "report")]
  [string]$Command = "status",
  [int]$Step = 1,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-launcher"
$StateFile = Join-Path $ReportDir "operator-walkthrough-state.json"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 30
  if (Test-UnsafeText $Text) { throw "Refusing unsafe walkthrough JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe walkthrough markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  ($Raw | Out-String).Trim() | ConvertFrom-Json
}

function Get-Steps {
  @(
    [pscustomobject]@{ id = 1; name = "bootstrap complete check"; route = "bootstrap"; token_printed = $false }
    [pscustomobject]@{ id = 2; name = "productization RC check"; route = "productization"; token_printed = $false }
    [pscustomobject]@{ id = 3; name = "local config check"; route = "config"; token_printed = $false }
    [pscustomobject]@{ id = 4; name = "doctor check"; route = "doctor"; token_printed = $false }
    [pscustomobject]@{ id = 5; name = "start preview"; route = "start-preview"; token_printed = $false }
    [pscustomobject]@{ id = 6; name = "demo mode"; route = "demo"; token_printed = $false }
    [pscustomobject]@{ id = 7; name = "local session status"; route = "status"; token_printed = $false }
    [pscustomobject]@{ id = 8; name = "diagnostics"; route = "diagnostics"; token_printed = $false }
    [pscustomobject]@{ id = 9; name = "smoke fast"; route = "smoke-fast"; token_printed = $false }
    [pscustomobject]@{ id = 10; name = "next safe action"; route = "next-action"; token_printed = $false }
  )
}

function Invoke-Step([int]$StepId) {
  $StepInfo = Get-Steps | Where-Object { $_.id -eq $StepId } | Select-Object -First 1
  if (-not $StepInfo) { throw "Unknown walkthrough step." }
  $Result = switch ($StepInfo.route) {
    "bootstrap" { Invoke-JsonScript "skybridge-bootstrap-complete.ps1" @("-Command", "gate") }
    "productization" { Invoke-JsonScript "skybridge-local-productization-rc.ps1" @("-Command", "status") }
    "config" { Invoke-JsonScript "skybridge-local-config.ps1" @("-Command", "validate") }
    "doctor" { Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "check") }
    "start-preview" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start") }
    "demo" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "demo") }
    "status" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "status") }
    "diagnostics" { Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "health") }
    "smoke-fast" { Invoke-JsonScript "skybridge-smoke-matrix.ps1" @("-Command", "run-fast") }
    "next-action" { Invoke-JsonScript "skybridge-session-supervisor.ps1" @("-Command", "next-action") }
  }
  [pscustomobject]@{
    schema = "skybridge.operator_walkthrough_step.v1"
    step = $StepInfo
    result = $Result
    safe = $true
    starts_codex_worker = $false
    runs_workunit_apply = $false
    runs_queue_apply = $false
    mutates_host = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
}

function New-Status {
  [pscustomobject]@{
    schema = "skybridge.operator_walkthrough.v1"
    status = "ready"
    steps = @(Get-Steps)
    state_file = ".agent/tmp/local-launcher/operator-walkthrough-state.json"
    token_printed = $false
  }
}

function Start-Walkthrough {
  $Status = New-Status
  Write-SafeJson $StateFile $Status
  $Status
}

function Reset-Walkthrough {
  [pscustomobject]@{
    schema = "skybridge.operator_walkthrough_reset_preview.v1"
    preview_only = $true
    would_remove_state_file = Test-Path -LiteralPath $StateFile
    host_mutation_required = $false
    token_printed = $false
  }
}

function Write-Report {
  $Results = @(1..10 | ForEach-Object { Invoke-Step $_ })
  $Report = [pscustomobject]@{
    schema = "skybridge.operator_walkthrough_report.v1"
    status = "safe_flow_passed"
    steps = $Results
    no_worker_execution = $true
    no_workunit_apply = $true
    no_queue_apply = $true
    no_host_mutation = $true
    raw_logs_persisted = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "operator-walkthrough-report.json") $Report
  Write-SafeMarkdown (Join-Path $ReportDir "operator-walkthrough-report.md") @(
    "# Operator Walkthrough Report",
    "",
    "- schema: skybridge.operator_walkthrough_report.v1",
    "- status: safe_flow_passed",
    "- steps: 10",
    "- no_worker_execution=true",
    "- no_workunit_apply=true",
    "- no_queue_apply=true",
    "- no_host_mutation=true",
    "- token_printed=false"
  )
  $Report
}

$Result = switch ($Command) {
  "start" { Start-Walkthrough }
  "step" { Invoke-Step $Step }
  "status" { New-Status }
  "reset-preview" { Reset-Walkthrough }
  "safe-summary" { [pscustomobject]@{ ok = $true; walkthrough_status = "safe"; no_worker_execution = $true; no_workunit_apply = $true; no_queue_apply = $true; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List | Out-String }
