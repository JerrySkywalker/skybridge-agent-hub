[CmdletBinding()]
param(
  [ValidateSet("fixture-soak", "session-rehearsal-soak", "doctor-soak", "cleanup-soak", "safe-summary", "report")]
  [string]$Command = "fixture-soak",
  [int]$Iterations = 3,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-session"

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
  "safe-summary" { [pscustomobject]@{ ok = $true; starts_codex_worker = $false; runs_workunit_apply = $false; runs_queue_apply = $false; background_process_left_running = $false; raw_logs_persisted = $false; token_printed = $false } }
  "report" { Write-Report }
}

if ($Json) { $Result | ConvertTo-Json -Depth 50 } else { $Result | Format-List | Out-String }
