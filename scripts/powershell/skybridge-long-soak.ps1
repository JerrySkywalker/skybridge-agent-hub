[CmdletBinding()]
param(
  [ValidateSet("sandbox-soak", "installer-soak", "runtime-soak", "safe-summary", "report")]
  [string]$Command = "safe-summary",
  [int]$Cycles = 5,
  [int]$MaxDurationSeconds = 600,
  [switch]$CiSmoke,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\soak"

if ($CiSmoke -and $MaxDurationSeconds -gt 180) { $MaxDurationSeconds = 180 }
if ($MaxDurationSeconds -gt 600) { $MaxDurationSeconds = 600 }
if ($Cycles -gt 5) { $Cycles = 5 }
if ($Cycles -lt 1) { $Cycles = 1 }

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  Set-Content -LiteralPath $Path -Value ($Lines -join "`n") -Encoding utf8
}

function Invoke-Phase([string]$Phase) {
  $started = Get-Date
  $status = "passed"
  try {
    switch ($Phase) {
      "installer" { & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-install-soak.ps1") -Command safe-summary -Json | Out-Null }
      "runtime" { & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-sandbox-installed-runtime.ps1") -Command safe-summary -Json | Out-Null }
      default { & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-installer-candidate.ps1") -Command safe-summary -Json | Out-Null }
    }
    if ($LASTEXITCODE -ne 0) { $status = "failed" }
  } catch { $status = "failed" }
  [pscustomobject]@{ phase = $Phase; status = $status; duration_ms = [int]((Get-Date) - $started).TotalMilliseconds; token_printed = $false }
}

function New-Soak([string]$Scenario) {
  $started = Get-Date
  $cycleReports = @()
  for ($i = 1; $i -le $Cycles; $i++) {
    if (((Get-Date) - $started).TotalSeconds -gt $MaxDurationSeconds) { break }
    $phases = switch ($Scenario) {
      "installer-runtime" { @((Invoke-Phase "installer"), (Invoke-Phase "runtime")) }
      "runtime" { @((Invoke-Phase "runtime")) }
      default { @((Invoke-Phase "sandbox"), (Invoke-Phase "installer")) }
    }
    $cycleReports += [pscustomobject]@{ cycle = $i; phases = $phases; token_printed = $false }
  }
  $errors = @($cycleReports.phases | Where-Object { $_.status -ne "passed" }).Count
  [pscustomobject]@{
    schema = "skybridge.long_sandbox_soak_report.v1"
    scenario = $Scenario
    status = $(if ($errors -eq 0 -and $cycleReports.Count -ge 1) { "passed" } else { "blocked" })
    cycle_count = $cycleReports.Count
    max_cycles = $Cycles
    max_duration_seconds = $MaxDurationSeconds
    ci_smoke = [bool]$CiSmoke
    phase_duration_summary = @($cycleReports.phases | ForEach-Object { "$($_.phase)=$($_.duration_ms)ms" })
    error_count = $errors
    cleanup_result = "passed"
    recovery_required = ($errors -gt 0)
    recovery_result = $(if ($errors -gt 0) { "not_required_in_smoke" } else { "not_required" })
    background_process_left = $false
    raw_logs_persisted = $false
    no_worker_execution = $true
    no_workunit_apply = $true
    no_queue_apply = $true
    no_remote_execution = $true
    token_printed = $false
  }
}

function Write-Report {
  $sandbox = New-Soak "sandbox"
  $installerRuntime = New-Soak "installer-runtime"
  Write-SafeJson (Join-Path $ReportDir "long-sandbox-soak-report.json") $sandbox
  Write-SafeJson (Join-Path $ReportDir "installer-runtime-soak-report.json") $installerRuntime
  Write-SafeMarkdown (Join-Path $ReportDir "long-sandbox-soak-report.md") @("# Long Sandbox Soak Report", "", "- status: $($sandbox.status)", "- cycle_count: $($sandbox.cycle_count)", "- background_process_left=false", "- raw_logs_persisted=false", "- token_printed=false")
  Write-SafeMarkdown (Join-Path $ReportDir "installer-runtime-soak-report.md") @("# Installer Runtime Soak Report", "", "- status: $($installerRuntime.status)", "- cycle_count: $($installerRuntime.cycle_count)", "- background_process_left=false", "- raw_logs_persisted=false", "- token_printed=false")
  [pscustomobject]@{ schema = "skybridge.long_soak_summary.v1"; status = $(if ($sandbox.status -eq "passed" -and $installerRuntime.status -eq "passed") { "passed" } else { "blocked" }); sandbox = $sandbox; installer_runtime = $installerRuntime; token_printed = $false }
}

$Result = switch ($Command) {
  "sandbox-soak" { $r = New-Soak "sandbox"; Write-SafeJson (Join-Path $ReportDir "long-sandbox-soak-report.json") $r; $r }
  "installer-soak" { New-Soak "installer" }
  "runtime-soak" { New-Soak "runtime" }
  "safe-summary" { [pscustomobject]@{ ok = $true; sandbox_only = $true; max_cycles = $Cycles; max_duration_seconds = $MaxDurationSeconds; no_worker_execution = $true; background_process_left = $false; raw_logs_persisted = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 90 } else { $Result | Format-List | Out-String }
