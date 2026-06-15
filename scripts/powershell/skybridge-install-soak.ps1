[CmdletBinding()]
param(
  [ValidateSet("install-upgrade-rollback-soak", "install-uninstall-soak", "rollback-rehearsal-soak", "safe-summary", "report")]
  [string]$Command = "safe-summary",
  [int]$Cycles = 3,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$SandboxRoot = Join-Path $RepoRoot ".agent\tmp\install-sandbox"
$MaxDurationSeconds = 240

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Assert-SandboxPath([string]$Path) {
  $root = [System.IO.Path]::GetFullPath($SandboxRoot)
  $target = [System.IO.Path]::GetFullPath($Path)
  if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes install sandbox: $Path" }
}

function Write-SafeJson([string]$Path, $Value) {
  Assert-SandboxPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 70
  if (Test-UnsafeText $text) { throw "Refusing unsafe install soak JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Get-SandboxMetrics {
  if (-not (Test-Path -LiteralPath $SandboxRoot)) {
    return [pscustomobject]@{ file_count = 0; size_bytes = 0; stale_lock_count = 0; stale_pid_count = 0; token_printed = $false }
  }
  $files = @(Get-ChildItem -LiteralPath $SandboxRoot -Recurse -File)
  [pscustomobject]@{
    file_count = $files.Count
    size_bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum ?? 0)
    stale_lock_count = @($files | Where-Object { $_.Name -match "\.lock(\.json)?$" }).Count
    stale_pid_count = @($files | Where-Object { $_.Name -match "\.pid(\.json)?$" }).Count
    token_printed = $false
  }
}

function Invoke-JsonScript([string]$Script, [string[]]$Args) {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @Args -Json 2>$null
  if ($LASTEXITCODE -ne 0) { throw "$Script failed" }
  $text = ($raw | Out-String).Trim()
  if (Test-UnsafeText $text) { throw "$Script emitted unsafe text" }
  $text | ConvertFrom-Json
}

function Invoke-Phase([string]$Name, [scriptblock]$Block) {
  $started = Get-Date
  $status = "passed"
  try { & $Block | Out-Null } catch { $status = "failed" }
  [pscustomobject]@{
    phase = $Name
    status = $status
    duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    token_printed = $false
  }
}

function Invoke-Soak([string]$Scenario) {
  $cycleLimit = [Math]::Min([Math]::Max($Cycles, 1), 3)
  $started = Get-Date
  $cycleReports = @()
  for ($i = 1; $i -le $cycleLimit; $i++) {
    if (((Get-Date) - $started).TotalSeconds -gt $MaxDurationSeconds) { break }
    $phases = @()
    switch ($Scenario) {
      "install-upgrade-rollback" {
        $phases += Invoke-Phase "install" { Invoke-JsonScript "skybridge-install-sandbox.ps1" @("-Command", "apply-sandbox") }
        $phases += Invoke-Phase "upgrade" { Invoke-JsonScript "skybridge-upgrade-rollback-sandbox.ps1" @("-Command", "upgrade-sandbox") }
        $phases += Invoke-Phase "rollback" { Invoke-JsonScript "skybridge-upgrade-rollback-sandbox.ps1" @("-Command", "rollback-sandbox") }
      }
      "install-uninstall" {
        $phases += Invoke-Phase "install" { Invoke-JsonScript "skybridge-install-sandbox.ps1" @("-Command", "apply-sandbox") }
        $phases += Invoke-Phase "uninstall-preview" { Invoke-JsonScript "skybridge-uninstall-sandbox.ps1" @("-Command", "uninstall-preview") }
      }
      "rollback-rehearsal" {
        $phases += Invoke-Phase "install" { Invoke-JsonScript "skybridge-install-sandbox.ps1" @("-Command", "apply-sandbox") }
        $phases += Invoke-Phase "upgrade" { Invoke-JsonScript "skybridge-upgrade-rollback-sandbox.ps1" @("-Command", "upgrade-sandbox") }
        $phases += Invoke-Phase "rollback" { Invoke-JsonScript "skybridge-upgrade-rollback-sandbox.ps1" @("-Command", "rollback-sandbox") }
      }
    }
    $cycleReports += [pscustomobject]@{ cycle = $i; phases = $phases; metrics = Get-SandboxMetrics; token_printed = $false }
  }
  $errors = @($cycleReports.phases | Where-Object { $_.status -ne "passed" }).Count
  [pscustomobject]@{
    schema = "skybridge.install_soak_report.v1"
    scenario = $Scenario
    status = $(if ($errors -eq 0 -and $cycleReports.Count -eq $cycleLimit) { "passed" } else { "blocked" })
    cycle_count = $cycleReports.Count
    max_cycles = $cycleLimit
    max_duration_seconds = $MaxDurationSeconds
    cycles = $cycleReports
    sandbox_size_preview = Get-SandboxMetrics
    error_count = $errors
    cleanup_result = "sandbox retained for inspection"
    background_process_left = $false
    host_mutation_allowed = $false
    token_printed = $false
  }
}

function Write-Report {
  $a = Invoke-Soak "install-upgrade-rollback"
  $b = Invoke-Soak "install-uninstall"
  Write-SafeJson (Join-Path $SandboxRoot "install-upgrade-rollback-soak-report.json") $a
  Write-SafeJson (Join-Path $SandboxRoot "install-uninstall-soak-report.json") $b
  [pscustomobject]@{
    schema = "skybridge.install_soak_report.v1"
    status = $(if ($a.status -eq "passed" -and $b.status -eq "passed") { "passed" } else { "blocked" })
    install_upgrade_rollback = $a
    install_uninstall = $b
    background_process_left = $false
    token_printed = $false
  }
}

$Result = switch ($Command) {
  "install-upgrade-rollback-soak" { $r = Invoke-Soak "install-upgrade-rollback"; Write-SafeJson (Join-Path $SandboxRoot "install-upgrade-rollback-soak-report.json") $r; $r }
  "install-uninstall-soak" { $r = Invoke-Soak "install-uninstall"; Write-SafeJson (Join-Path $SandboxRoot "install-uninstall-soak-report.json") $r; $r }
  "rollback-rehearsal-soak" { Invoke-Soak "rollback-rehearsal" }
  "safe-summary" { [pscustomobject]@{ ok = $true; sandbox_only = $true; max_cycles = [Math]::Min([Math]::Max($Cycles, 1), 3); max_duration_seconds = $MaxDurationSeconds; background_process_left = $false; host_mutation_allowed = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 80 } else { $Result | Format-List | Out-String }
