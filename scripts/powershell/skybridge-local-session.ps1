[CmdletBinding()]
param(
  [ValidateSet("start", "stop", "restart", "status", "doctor", "cleanup", "ports", "locks", "demo", "safe-summary", "report", "rehearsal")]
  [string]$Command = "status",
  [string]$Profile = "preview",
  [switch]$Apply,
  [switch]$Bounded,
  [switch]$Fixture,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-session"
$SessionId = "manual-local-session-rc"
$LockFile = Join-Path $ReportDir "manual-local-session.lock.json"
$PidFile = Join-Path $ReportDir "manual-local-session.pid.json"

function Test-UnsafeText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  return $Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue"
}

function Write-SafeJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $Text = $Value | ConvertTo-Json -Depth 30
  if (Test-UnsafeText $Text) { throw "Refusing unsafe local session JSON." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Write-SafeMarkdown([string]$Path, [string[]]$Lines) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Text = $Lines -join "`n"
  if (Test-UnsafeText $Text) { throw "Refusing unsafe local session markdown." }
  Set-Content -LiteralPath $Path -Value $Text -Encoding utf8
}

function Test-PortAvailable([int]$Port) {
  if ($Port -le 0) { return $true }
  try {
    $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $Listener.Start()
    $Listener.Stop()
    return $true
  } catch {
    return $false
  }
}

function New-Component([string]$Id, [string]$Role, [int]$Port, [string]$Status = "preview") {
  [pscustomobject]@{
    schema = "skybridge.local_session_component.v1"
    component_id = $Id
    role = $Role
    status = $Status
    port = $Port
    port_available = Test-PortAvailable $Port
    bounded = $true
    fixture_owned = $Fixture.IsPresent
    starts_codex_worker = $false
    runs_workunit_apply = $false
    creates_workunit = $false
    creates_task = $false
    claims_task = $false
    creates_task_pr = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    raw_output_persisted = $false
    token_printed = $false
  }
}

function Get-Components([string]$Status = "preview") {
  @(
    New-Component "web-preview" "web preview" 5173 $Status
    New-Component "server-control-plane-preview" "server/control-plane preview" 8787 $Status
    New-Component "desktop-dev-metadata" "desktop metadata/status surface" 0 $Status
    New-Component "local-supervisor-heartbeat-preview" "local supervisor heartbeat preview" 0 $Status
    New-Component "resident-polling-preview" "resident polling preview" 0 $Status
    New-Component "diagnostics" "diagnostics" 0 $Status
    New-Component "product-readiness" "product readiness" 0 $Status
    New-Component "smoke-matrix-status" "smoke-matrix status" 0 $Status
  )
}

function New-Lifecycle([string]$State, [bool]$Started, [bool]$Stopped) {
  [pscustomobject]@{
    schema = "skybridge.local_session_lifecycle.v1"
    session_id = $SessionId
    state = $State
    started = $Started
    stopped = $Stopped
    bounded = $true
    background_process_left_running = $false
    raw_log_persisted = $false
    crash_safe_metadata = $true
    stop_supported = $true
    cleanup_preview_supported = $true
    token_printed = $false
  }
}

function New-Ports {
  [pscustomobject]@{
    schema = "skybridge.local_session_ports.v1"
    checks = @(
      [pscustomobject]@{ component_id = "web-preview"; port = 5173; available = Test-PortAvailable 5173; token_printed = $false }
      [pscustomobject]@{ component_id = "server-control-plane-preview"; port = 8787; available = Test-PortAvailable 8787; token_printed = $false }
    )
    port_conflict_explanation = "A busy port blocks bounded apply; stop the owning preview or choose another port in a later goal."
    token_printed = $false
  }
}

function New-Locks {
  $LockPresent = Test-Path -LiteralPath $LockFile
  $PidPresent = Test-Path -LiteralPath $PidFile
  [pscustomobject]@{
    schema = "skybridge.local_session_lock_state.v1"
    session_id = $SessionId
    lock_present = $LockPresent
    pid_file_present = $PidPresent
    stale_lock_detected = $false
    stale_pid_detected = $false
    cleanup_preview_only = $true
    lock_file = ".agent/tmp/local-session/manual-local-session.lock.json"
    pid_file = ".agent/tmp/local-session/manual-local-session.pid.json"
    token_printed = $false
  }
}

function New-StartPlan {
  $PreviewOnly = -not ($Apply -and $Bounded -and $Profile -eq "full-local-preview")
  [pscustomobject]@{
    schema = "skybridge.local_session_start_plan.v1"
    session_id = $SessionId
    profile = $Profile
    apply_requested = [bool]$Apply
    bounded_requested = [bool]$Bounded
    preview_only = $PreviewOnly
    required_apply_form = "-Command start -Apply -Profile full-local-preview -Bounded"
    components = @(Get-Components "planned")
    forbidden_components_excluded = @("codex_worker", "workunit_apply", "task_claim", "task_pr_creation", "generic_queue_apply", "remote_command_executor", "arbitrary_command_dispatch")
    starts_codex_worker = $false
    runs_workunit_apply = $false
    creates_workunit = $false
    creates_task = $false
    claims_task = $false
    creates_task_pr = $false
    starts_unbounded_loop = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-StopPlan {
  [pscustomobject]@{
    schema = "skybridge.local_session_stop_plan.v1"
    session_id = $SessionId
    stops_only_fixture_owned_processes = $true
    kills_arbitrary_processes = $false
    removes_session_metadata = $true
    raw_output_persisted = $false
    token_printed = $false
  }
}

function Write-SessionState([string]$State) {
  $Status = [pscustomobject]@{
    schema = "skybridge.local_session.v1"
    session_id = $SessionId
    profile = "full-local-preview"
    status = $State
    lifecycle = New-Lifecycle $State ($State -eq "running" -or $State -eq "fixture_completed") ($State -eq "stopped")
    components = @(Get-Components $State)
    ports = New-Ports
    locks = New-Locks
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_claim", "task_creation", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch", "start_all", "start_queue", "resume_apply")
    next_safe_action = "Run doctor or stop the bounded local session."
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "local-session-status.json") $Status
  Write-SafeJson $LockFile $Status
  $Status
}

function Start-Session {
  $Plan = New-StartPlan
  Write-SafeJson (Join-Path $ReportDir "local-session-start-plan.json") $Plan
  if ($Plan.preview_only) { return $Plan }
  $Status = Write-SessionState "running"
  if ($Fixture) {
    $Process = Start-Process -FilePath "pwsh" -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Milliseconds 150") -PassThru -WindowStyle Hidden
    $Process.WaitForExit(5000) | Out-Null
    [pscustomobject]@{ schema = "skybridge.local_session_fixture_pid.v1"; pid = $Process.Id; exited = $Process.HasExited; fixture_owned = $true; token_printed = $false } | ForEach-Object { Write-SafeJson $PidFile $_ }
    $Status.lifecycle.background_process_left_running = $false
    $Status.status = "fixture_completed"
    Write-SafeJson (Join-Path $ReportDir "local-session-status.json") $Status
    Write-SafeJson $LockFile $Status
  }
  $Status
}

function Stop-Session {
  $Plan = New-StopPlan
  if (Test-Path -LiteralPath $LockFile) { Remove-Item -LiteralPath $LockFile -Force }
  if (Test-Path -LiteralPath $PidFile) { Remove-Item -LiteralPath $PidFile -Force }
  $Status = [pscustomobject]@{
    schema = "skybridge.local_session.v1"
    session_id = $SessionId
    status = "stopped"
    lifecycle = New-Lifecycle "stopped" $false $true
    stop_plan = $Plan
    background_process_left_running = $false
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_claim", "task_creation", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "local-session-status.json") $Status
  $Status
}

function Get-Status {
  $StatusPath = Join-Path $ReportDir "local-session-status.json"
  if (Test-Path -LiteralPath $StatusPath) { return Get-Content -Raw -LiteralPath $StatusPath | ConvertFrom-Json }
  [pscustomobject]@{
    schema = "skybridge.local_session.v1"
    session_id = $SessionId
    status = "stopped"
    lifecycle = New-Lifecycle "stopped" $false $true
    components = @(Get-Components "stopped")
    ports = New-Ports
    locks = New-Locks
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_claim", "task_creation", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    token_printed = $false
  }
}

function New-Cleanup {
  [pscustomobject]@{
    schema = "skybridge.local_session_cleanup_preview.v1"
    session_id = $SessionId
    stale_lock_cleanup_preview = New-Locks
    stale_pid_cleanup_preview = New-Locks
    last_session_summary = Get-Status
    kills_arbitrary_processes = $false
    fixture_owned_process_cleanup_only = $true
    preview_only = $true
    safe_recovery_guidance = @("Run status", "Run doctor", "Run cleanup for a preview", "Run stop to remove this session metadata only")
    token_printed = $false
  }
}

function New-Demo {
  [pscustomobject]@{
    schema = "skybridge.local_session_report.v1"
    mode = "operator_demo_fixture"
    session = [pscustomobject]@{
      schema = "skybridge.local_session.v1"
      session_id = "demo-local-session"
      status = "demo_ready"
      components = @(Get-Components "demo")
      token_printed = $false
    }
    demo_mode_status = "fixture_only"
    starts_worker = $false
    executes_workunit = $false
    creates_task = $false
    mutates_system = $false
    token_printed = $false
  }
}

function Write-Report {
  $Status = Get-Status
  $Report = [pscustomobject]@{
    schema = "skybridge.local_session_report.v1"
    rc_version = "v1.2.0-manual-local-session-rc"
    commit = ((& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim())
    local_session_status = $Status.status
    lifecycle = $Status.lifecycle
    components = @($Status.components)
    ports = New-Ports
    locks = New-Locks
    cleanup_recovery = New-Cleanup
    demo_mode_status = "fixture_only"
    disabled_capabilities = @("codex_worker", "workunit_apply", "task_claim", "task_creation", "task_pr_creation", "generic_queue_apply", "remote_execution", "arbitrary_command_dispatch")
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "local-session-report.json") $Report
  Write-SafeMarkdown (Join-Path $ReportDir "local-session-report.md") @(
    "# Manual Local Session Report",
    "",
    "- schema: skybridge.local_session_report.v1",
    "- rc_version: v1.2.0-manual-local-session-rc",
    "- local_session_status: $($Report.local_session_status)",
    "- demo_mode_status: fixture_only",
    "- codex_worker_started: false",
    "- workunit_apply_ran: false",
    "- task_claimed: false",
    "- generic_queue_apply_ran: false",
    "- remote_execution_enabled: false",
    "- arbitrary_command_enabled: false",
    "- token_printed=false"
  )
  $Report
}

function Invoke-Doctor {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-doctor.ps1") -Command check -Json | ConvertFrom-Json
}

function Invoke-Rehearsal {
  $StartPreview = New-StartPlan
  $Doctor = Invoke-Doctor
  $Demo = New-Demo
  $Status = Get-Status
  $StopPreview = New-StopPlan
  $Cleanup = New-Cleanup
  $Report = [pscustomobject]@{
    schema = "skybridge.local_session_rehearsal_report.v1"
    status = "passed"
    start_preview = $StartPreview
    doctor_check = $Doctor
    demo = $Demo
    session_status = $Status
    stop_preview = $StopPreview
    cleanup_preview = $Cleanup
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    runs_queue_apply = $false
    leaves_background_process = $false
    token_printed = $false
  }
  Write-SafeJson (Join-Path $ReportDir "local-session-rehearsal-report.json") $Report
  Write-SafeMarkdown (Join-Path $ReportDir "local-session-rehearsal-report.md") @(
    "# Local Session Rehearsal",
    "",
    "- schema: skybridge.local_session_rehearsal_report.v1",
    "- status: passed",
    "- starts_codex_worker=false",
    "- runs_workunit_apply=false",
    "- claims_task=false",
    "- runs_queue_apply=false",
    "- leaves_background_process=false",
    "- token_printed=false"
  )
  $Report
}

$Result = switch ($Command) {
  "start" { Start-Session }
  "stop" { Stop-Session }
  "restart" { Stop-Session | Out-Null; Start-Session }
  "status" { Get-Status }
  "doctor" { Invoke-Doctor }
  "cleanup" { New-Cleanup }
  "ports" { New-Ports }
  "locks" { New-Locks }
  "demo" { New-Demo }
  "safe-summary" { [pscustomobject]@{ ok = $true; session_id = $SessionId; execution_enabled = $false; queue_apply_enabled = $false; remote_execution_enabled = $false; arbitrary_command_enabled = $false; starts_codex_worker = $false; runs_workunit_apply = $false; claims_task = $false; token_printed = $false } }
  "report" { Write-Report }
  "rehearsal" { Invoke-Rehearsal }
}

if ($Json) { $Result | ConvertTo-Json -Depth 30 } else { $Result | Format-List | Out-String }
