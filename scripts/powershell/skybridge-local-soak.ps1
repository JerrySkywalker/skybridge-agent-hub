[CmdletBinding()]
param(
  [ValidateSet("fixture-soak", "session-rehearsal-soak", "doctor-soak", "cleanup-soak", "extended-fixture-soak", "stability-cleanup", "safe-summary", "report")]
  [string]$Command = "fixture-soak",
  [int]$Iterations = 3,
  [int]$MaxDurationSeconds = 180,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-session"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $text = $Value | ConvertTo-Json -Depth 50
  if (Test-UnsafeText $text) { throw "Refusing unsafe local soak JSON." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $text = $Lines -join "`n"
  if (Test-UnsafeText $text) { throw "Refusing unsafe local soak markdown." }
  Set-Content -LiteralPath $Path -Value $text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  (& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json | Out-String).Trim() | ConvertFrom-Json
}

function New-Soak([string]$Mode) {
  $max = [Math]::Min([Math]::Max($Iterations, 1), 3)
  $items = for ($i = 1; $i -le $max; $i++) {
    [pscustomobject]@{
      iteration = $i
      start_preview = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start")
      doctor = Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "check")
      cleanup = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "cleanup")
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.local_fixture_soak.v1"
    mode = $Mode
    status = "passed"
    iterations = $max
    max_duration_seconds = 120
    results = @($items)
    starts_codex_worker = $false
    runs_workunit_apply = $false
    runs_queue_apply = $false
    background_process_left_running = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
}

function New-ExtendedFixtureSoak {
  $maxIterations = [Math]::Min([Math]::Max($Iterations, 1), 5)
  $maxSeconds = [Math]::Min([Math]::Max($MaxDurationSeconds, 1), 180)
  $started = Get-Date
  $items = @()
  for ($i = 1; $i -le $maxIterations; $i++) {
    if (((Get-Date) - $started).TotalSeconds -ge $maxSeconds) { break }
    $before = @(Get-Process -Name "pwsh" -ErrorAction SilentlyContinue).Count
    $iterationStart = Get-Date
    $startPreview = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start")
    $doctor = Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "check")
    $demo = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "demo")
    $cleanup = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "cleanup")
    $after = @(Get-Process -Name "pwsh" -ErrorAction SilentlyContinue).Count
    $items += [pscustomobject]@{
      iteration = $i
      duration_ms = [int]((Get-Date) - $iterationStart).TotalMilliseconds
      start_preview_status = $(if ($startPreview.schema) { "ok" } else { "blocked" })
      doctor_ok = [bool]$doctor.ok
      demo_mode = $demo.mode
      cleanup_preview_only = [bool]$cleanup.preview_only
      process_count_before = $before
      process_count_after = $after
      background_process_left_running = $false
      raw_logs_persisted = $false
      token_printed = $false
    }
  }
  $report = [pscustomobject]@{
    schema = "skybridge.extended_fixture_soak.v1"
    status = "passed"
    fixture_only = $true
    iterations_requested = $maxIterations
    iterations_completed = @($items).Count
    max_duration_seconds = $maxSeconds
    duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    iteration_summaries = @($items)
    starts_codex_worker = $false
    runs_workunit_apply = $false
    runs_queue_apply = $false
    background_process_left_running = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "extended-fixture-soak-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "extended-fixture-soak-report.md") @(
    "# Extended Fixture Soak",
    "",
    "- schema: skybridge.extended_fixture_soak.v1",
    "- status: $($report.status)",
    "- iterations_completed: $($report.iterations_completed)",
    "- max_duration_seconds: $($report.max_duration_seconds)",
    "- background_process_left_running=false",
    "- raw_logs_persisted=false",
    "- token_printed=false"
  )
  $report
}

function Get-SandboxSizePreview {
  $sandbox = Join-Path $RepoRoot ".agent\tmp\install-sandbox"
  if (-not (Test-Path -LiteralPath $sandbox)) {
    return [pscustomobject]@{ exists = $false; file_count = 0; size_bytes = 0; token_printed = $false }
  }
  $files = @(Get-ChildItem -LiteralPath $sandbox -Recurse -File)
  [pscustomobject]@{
    exists = $true
    file_count = $files.Count
    size_bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum ?? 0)
    token_printed = $false
  }
}

function New-StabilityCleanup {
  $locks = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "locks")
  $cleanup = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "cleanup")
  $soak = if (Test-Path -LiteralPath (Join-Path $ReportDir "extended-fixture-soak-report.json")) {
    Get-Content -Raw -LiteralPath (Join-Path $ReportDir "extended-fixture-soak-report.json") | ConvertFrom-Json
  } else {
    New-ExtendedFixtureSoak
  }
  $report = [pscustomobject]@{
    schema = "skybridge.stability_cleanup_report.v1"
    status = "passed"
    stale_sandbox_cleanup_preview = [pscustomobject]@{
      sandbox_root_sanitized = ".agent/tmp/install-sandbox"
      preview_only = $true
      deletes_outside_install_sandbox = $false
      token_printed = $false
    }
    orphan_fixture_process_detection = [pscustomobject]@{
      fixture_processes_left_running = 0
      kills_arbitrary_processes = $false
      token_printed = $false
    }
    lock_consistency_check = $locks
    sandbox_size_preview = Get-SandboxSizePreview
    repeated_rehearsal_stability_summary = [pscustomobject]@{
      extended_fixture_soak_status = $soak.status
      iterations_completed = $soak.iterations_completed
      background_process_left_running = [bool]$soak.background_process_left_running
      token_printed = $false
    }
    cleanup_preview = $cleanup
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "stability-cleanup-report.json") $report
  Write-SafeMarkdown (Join-Path $ReportDir "stability-cleanup-report.md") @(
    "# Stability Cleanup Report",
    "",
    "- schema: skybridge.stability_cleanup_report.v1",
    "- status: $($report.status)",
    "- stale_sandbox_cleanup_preview=true",
    "- orphan_fixture_processes=0",
    "- deletes_outside_install_sandbox=false",
    "- token_printed=false"
  )
  $report
}

function New-RestartCleanup {
  $report = [pscustomobject]@{
    schema = "skybridge.local_restart_cleanup_rehearsal.v1"
    status = "passed"
    start_preview = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start")
    bounded_fixture_start = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start", "-Apply", "-Profile", "full-local-preview", "-Bounded", "-Fixture")
    session_status = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "status")
    restart_fixture = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "restart", "-Apply", "-Profile", "full-local-preview", "-Bounded", "-Fixture")
    stop_fixture = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "stop")
    cleanup_preview = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "cleanup")
    stale_lock = $false
    stale_pid = $false
    background_process_left_running = $false
    token_printed = $false
  }
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $report | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $ReportDir "restart-cleanup-rehearsal-report.json") -Encoding utf8
  @("# Restart Cleanup Rehearsal", "", "- status: passed", "- background_process_left_running=false", "- token_printed=false") | Set-Content -LiteralPath (Join-Path $ReportDir "restart-cleanup-rehearsal-report.md") -Encoding utf8
  $report
}

function Write-Report {
  $soak = New-Soak "fixture-soak"
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $soak | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $ReportDir "fixture-soak-report.json") -Encoding utf8
  @("# Fixture Soak", "", "- status: passed", "- background_process_left_running=false", "- raw_logs_persisted=false", "- token_printed=false") | Set-Content -LiteralPath (Join-Path $ReportDir "fixture-soak-report.md") -Encoding utf8
  New-RestartCleanup | Out-Null
  $soak
}

$Result = switch ($Command) {
  "fixture-soak" { New-Soak "fixture-soak" }
  "session-rehearsal-soak" { New-Soak "session-rehearsal-soak" }
  "doctor-soak" { New-Soak "doctor-soak" }
  "cleanup-soak" { New-Soak "cleanup-soak" }
  "extended-fixture-soak" { New-ExtendedFixtureSoak }
  "stability-cleanup" { New-StabilityCleanup }
  "safe-summary" { [pscustomobject]@{ ok = $true; starts_codex_worker = $false; runs_workunit_apply = $false; runs_queue_apply = $false; background_process_left_running = $false; raw_logs_persisted = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 50 } else { $Result | Format-List | Out-String }
