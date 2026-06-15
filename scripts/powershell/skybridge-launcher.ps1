[CmdletBinding()]
param(
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-launcher"
$DocsLink = "docs/dev/LAUNCHER_ERROR_MODEL.md"
$AllowedCommands = @("status", "start-preview", "start-local", "stop-local", "restart-local", "doctor", "demo", "diagnostics", "readiness", "smoke-fast", "smoke-bootstrap", "safe-summary", "report", "demo-doctor-rehearsal")

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)[;&|`$<>]|\b(start-all|start-queue|resume\s+-Apply|codex|workunit|claim|queue\s*apply|registry|scheduled\s*task|service|powercfg)\b|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function New-SafeError([string]$Code, [string]$Message, [int]$ExitCode = 2) {
  [pscustomobject]@{
    schema = "skybridge.launcher_safe_error.v1"
    ok = $false
    code = $Code
    message = $Message
    next_safe_action = "Run .\skybridge.ps1 status or .\skybridge.ps1 start-preview."
    docs_link = $DocsLink
    exit_code = $ExitCode
    accepts_arbitrary_shell = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    mutates_host = $false
    token_printed = $false
  }
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 30
  if (Test-UnsafeText $Text) { throw "Refusing unsafe launcher JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe launcher markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  ($Raw | Out-String).Trim() | ConvertFrom-Json
}

function New-LauncherCommand([string]$Name, [string]$Summary) {
  [pscustomobject]@{
    schema = "skybridge.launcher_command.v1"
    command = $Name
    summary = $Summary
    accepts_arbitrary_shell = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    mutates_host = $false
    token_printed = $false
  }
}

function Get-Commands {
  @(
    New-LauncherCommand "status" "Safe help and status."
    New-LauncherCommand "start-preview" "Preview local session start plan."
    New-LauncherCommand "start-local" "Explicit bounded local session apply using full-local-preview."
    New-LauncherCommand "stop-local" "Stop local session metadata."
    New-LauncherCommand "restart-local" "Restart bounded local session metadata."
    New-LauncherCommand "doctor" "Run local doctor check."
    New-LauncherCommand "demo" "Show fixture-only demo data."
    New-LauncherCommand "diagnostics" "Run safe diagnostics health."
    New-LauncherCommand "readiness" "Run product readiness summary."
    New-LauncherCommand "smoke-fast" "Run smoke matrix fast group."
    New-LauncherCommand "smoke-bootstrap" "Run smoke matrix bootstrap-complete group."
    New-LauncherCommand "safe-summary" "Print safe launcher summary."
    New-LauncherCommand "report" "Write launcher report."
    New-LauncherCommand "demo-doctor-rehearsal" "Run integrated demo, doctor, walkthrough, readiness and smoke-fast rehearsal."
  )
}

function New-Route([string]$Name, [object]$Result) {
  [pscustomobject]@{
    schema = "skybridge.launcher_route.v1"
    command = $Name
    routed = $true
    result = $Result
    accepts_arbitrary_shell = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    token_printed = $false
  }
}

function New-Status {
  [pscustomobject]@{
    schema = "skybridge.repo_local_launcher.v1"
    status = "ready"
    default_action = "status"
    start_preview_default = $true
    commands = @(Get-Commands)
    reports_dir = ".agent/tmp/local-launcher"
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function Invoke-Route([string]$Name) {
  if (Test-UnsafeText $Name) { return New-SafeError "unsafe_command_rejected" "Command text contains shell metacharacters or blocked execution/host mutation words." 64 }
  if ($AllowedCommands -notcontains $Name) { return New-SafeError "unknown_command" "Unknown launcher command '$Name' was rejected. No command was run." 64 }
  $Result = switch ($Name) {
    "status" { New-Status }
    "start-preview" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start") }
    "start-local" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start", "-Apply", "-Profile", "full-local-preview", "-Bounded") }
    "stop-local" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "stop") }
    "restart-local" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "restart", "-Apply", "-Profile", "full-local-preview", "-Bounded") }
    "doctor" { Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "check") }
    "demo" { Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "demo") }
    "diagnostics" { Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "health") }
    "readiness" { Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "product-readiness") }
    "smoke-fast" { Invoke-JsonScript "skybridge-smoke-matrix.ps1" @("-Command", "run-fast") }
    "smoke-bootstrap" { Invoke-JsonScript "skybridge-smoke-matrix.ps1" @("-Command", "run-bootstrap-complete") }
    "safe-summary" { [pscustomobject]@{ ok = $true; launcher_status = "ready"; execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; starts_codex_worker = $false; runs_workunit_apply = $false; claims_task = $false; token_printed = $false } }
    "report" { Write-Report }
    "demo-doctor-rehearsal" { Invoke-DemoDoctorRehearsal }
  }
  New-Route $Name $Result
}

function Invoke-DemoDoctorRehearsal {
  $Report = [pscustomobject]@{
    schema = "skybridge.demo_doctor_rehearsal_report.v1"
    status = "passed"
    launcher_demo = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "demo")
    operator_walkthrough = Invoke-JsonScript "skybridge-operator-walkthrough.ps1" @("-Command", "status")
    local_doctor = Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "check")
    product_readiness = Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "product-readiness")
    smoke_fast = Invoke-JsonScript "skybridge-smoke-matrix.ps1" @("-Command", "run-fast")
    safe_summary = [pscustomobject]@{ execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; token_printed = $false }
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    leaves_background_process = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "demo-doctor-rehearsal-report.json") $Report
  Write-SafeMarkdown (Join-Path $ReportDir "demo-doctor-rehearsal-report.md") @(
    "# Demo Doctor Rehearsal",
    "",
    "- schema: skybridge.demo_doctor_rehearsal_report.v1",
    "- status: passed",
    "- starts_codex_worker=false",
    "- runs_workunit_apply=false",
    "- runs_queue_apply=false",
    "- token_printed=false"
  )
  $Report
}

function Write-Report {
  $Status = New-Status
  $Report = [pscustomobject]@{
    schema = "skybridge.launcher_report.v1"
    rc_version = "v1.3.0-repo-local-launcher-rc"
    commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    launcher_status = "ready"
    command_router_status = "fixed_allowlist_only"
    status = $Status
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_claim", "task_creation", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "launcher-status.json") $Status
  Write-SafeJson (Join-Path $ReportDir "launcher-report.json") $Report
  Write-SafeMarkdown (Join-Path $ReportDir "launcher-report.md") @(
    "# Repo-local Launcher Report",
    "",
    "- schema: skybridge.launcher_report.v1",
    "- rc_version: v1.3.0-repo-local-launcher-rc",
    "- launcher_status: ready",
    "- command_router_status: fixed_allowlist_only",
    "- execution_enabled=false",
    "- queue_apply_enabled=false",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- token_printed=false"
  )
  $Report
}

$Result = Invoke-Route $Command
if ($Result.schema -eq "skybridge.launcher_safe_error.v1") {
  if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List | Out-String }
  exit $Result.exit_code
}
if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List | Out-String }
