param(
  [ValidateSet(
    "status",
    "heartbeat-once",
    "heartbeat-preview",
    "lock-status",
    "stale-lock-check",
    "resource-status",
    "resident-summary",
    "safe-report",
    "pause-preview",
    "drain-preview",
    "emergency-stop-preview",
    "clear-preview-holds",
    "control-state",
    "action-matrix",
    "evidence-summary",
    "no-execution-gate"
  )]
  [string]$Command = "status",
  [string]$WorkerId = "laptop-zenbookduo",
  [string]$DeviceId = "local-fixture-device",
  [string]$StateDir = ".agent/tmp/local-supervisor",
  [string]$ReportDir = ".agent/tmp/desktop-resident-worker",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$CoreModule = Join-Path $ScriptDir "lib/Skybridge.Core.psm1"
$ResourceGateModule = Join-Path $ScriptDir "lib/Skybridge.ResourceGate.psm1"
Import-Module $CoreModule -Force
Import-Module $ResourceGateModule -Force

function Resolve-RepoPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Assert-IgnoredLocalPath {
  param([string]$Path)
  $Resolved = Resolve-RepoPath $Path
  $AllowedRoots = @(
    [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/local-supervisor")),
    [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/desktop-resident-worker"))
  )
  foreach ($Root in $AllowedRoots) {
    if ($Resolved.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $Resolved
    }
  }
  throw "Unsafe output path outside ignored local supervisor directories: $Path"
}

function ConvertTo-SafeJsonText {
  param([object]$Value)
  $Text = $Value | ConvertTo-Json -Depth 20
  if ($Text -match '(?i)(authorization:\s*bearer|bearer\s+[a-z0-9._-]{20,}|openai_api_key|private_key|BEGIN (RSA |OPENSSH |)PRIVATE KEY|cookie)') {
    throw "Unsafe secret-looking text detected in local supervisor output"
  }
  if ($Text -match '"token_printed"\s*:\s*true') {
    throw "token_printed=true is forbidden"
  }
  return $Text
}

function Write-SafeJson {
  param([string]$Path, [object]$Value)
  $Resolved = Assert-IgnoredLocalPath $Path
  $Parent = Split-Path -Parent $Resolved
  if (-not (Test-Path -LiteralPath $Parent)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
  }
  $Text = ConvertTo-SafeJsonText -Value $Value
  Set-Content -LiteralPath $Resolved -Value $Text -Encoding UTF8
  return $Resolved
}

function Write-SafeMarkdown {
  param([string]$Path, [string[]]$Lines)
  $Resolved = Assert-IgnoredLocalPath $Path
  $Parent = Split-Path -Parent $Resolved
  if (-not (Test-Path -LiteralPath $Parent)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
  }
  $Text = $Lines -join [Environment]::NewLine
  if ($Text -match '(?i)(authorization:\s*bearer|bearer\s+[a-z0-9._-]{20,}|openai_api_key|private_key|BEGIN (RSA |OPENSSH |)PRIVATE KEY|cookie)') {
    throw "Unsafe secret-looking text detected in local supervisor markdown"
  }
  if ($Text -match 'token_printed=true') {
    throw "token_printed=true is forbidden"
  }
  Set-Content -LiteralPath $Resolved -Value $Text -Encoding UTF8
  return $Resolved
}

function Get-GitScalar {
  param([string[]]$GitArgs, [string]$Fallback)
  try {
    $Output = & git @GitArgs 2>$null
    if ($LASTEXITCODE -eq 0 -and $Output) {
      return (($Output | Select-Object -First 1) -as [string]).Trim()
    }
  } catch {
    return $Fallback
  }
  return $Fallback
}

function Get-AlphaReadiness {
  $AlphaScript = Join-Path $ScriptDir "skybridge-boinc-v1-alpha.ps1"
  if (-not (Test-Path -LiteralPath $AlphaScript)) {
    return [ordered]@{
      alpha_id = "boinc-v1-alpha-215"
      two_workunit_alpha_completed = $false
      workunit_a_completed = $false
      workunit_b_completed = $false
      workunit_c_present = $false
      no_next_execution_authorized = $true
      token_printed = $false
    }
  }
  $Raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $AlphaScript -Command alpha-completion-readiness -Json
  if ($LASTEXITCODE -ne 0) {
    throw "Alpha readiness check failed"
  }
  $Parsed = $Raw | ConvertFrom-Json
  return [ordered]@{
    alpha_id = $Parsed.alpha_id
    two_workunit_alpha_completed = [bool]$Parsed.two_workunit_alpha_completed
    workunit_a_completed = [bool]$Parsed.workunit_a_completed
    workunit_b_completed = [bool]$Parsed.workunit_b_completed
    workunit_c_present = [bool]$Parsed.workunit_c_present
    no_next_execution_authorized = [bool]$Parsed.no_next_execution_authorized
    token_printed = $false
  }
}

function Get-ControlState {
  $Path = Resolve-RepoPath (Join-Path $StateDir "control-preview-state.json")
  if (Test-Path -LiteralPath $Path) {
    $Existing = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    return [ordered]@{
      schema = "skybridge.local_supervisor_control_preview.v1"
      pause_after_current = [bool]$Existing.pause_after_current
      drain_after_current = [bool]$Existing.drain_after_current
      pause_new_claims = [bool]$Existing.pause_new_claims
      emergency_stop_requested = [bool]$Existing.emergency_stop_requested
      operator_hold = [bool]$Existing.operator_hold
      review_hold = [bool]$Existing.review_hold
      resource_gate_hold = [bool]$Existing.resource_gate_hold
      no_next_execution_authorized = $true
      token_printed = $false
    }
  }
  return [ordered]@{
    schema = "skybridge.local_supervisor_control_preview.v1"
    pause_after_current = $false
    drain_after_current = $false
    pause_new_claims = $false
    emergency_stop_requested = $false
    operator_hold = $false
    review_hold = $false
    resource_gate_hold = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function Set-ControlState {
  param([string]$Action)
  $State = Get-ControlState
  if ($Action -eq "pause-preview") {
    $State.pause_after_current = $true
    $State.pause_new_claims = $true
    $State.operator_hold = $true
  } elseif ($Action -eq "drain-preview") {
    $State.drain_after_current = $true
    $State.pause_new_claims = $true
    $State.operator_hold = $true
  } elseif ($Action -eq "emergency-stop-preview") {
    $State.emergency_stop_requested = $true
    $State.pause_new_claims = $true
    $State.operator_hold = $true
  } elseif ($Action -eq "clear-preview-holds") {
    $State.pause_after_current = $false
    $State.drain_after_current = $false
    $State.pause_new_claims = $false
    $State.emergency_stop_requested = $false
    $State.operator_hold = $false
    $State.review_hold = $false
    $State.resource_gate_hold = $false
  }
  $State.action = $Action
  $State.preview_only = $true
  $State.execution_enabled = $false
  $State.queue_apply_enabled = $false
  $State.task_claim_enabled = $false
  $State.codex_execution_enabled = $false
  $State.updated_at = (Get-Date).ToUniversalTime().ToString("o")
  $State.path = Write-SafeJson -Path (Join-Path $StateDir "control-preview-state.json") -Value $State
  return $State
}

function New-LockState {
  return [ordered]@{
    schema = "skybridge.local_supervisor_lock_state.v1"
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    open_review_hold = $false
    token_printed = $false
  }
}

function New-ResourceStatus {
  $Gate = Invoke-SkybridgeResourceGate -RunId "desktop-resident-worker-v1" -Fixture "ac-ok"
  return [ordered]@{
    schema = "skybridge.local_supervisor_resource_status.v1"
    resource_gate_required = $true
    can_run_one_at_a_time = [bool]$Gate.can_run_one_at_a_time
    status = if ($Gate.can_run_one_at_a_time) { "pass" } else { "blocked" }
    blockers = @($Gate.blockers)
    warnings = @($Gate.warnings)
    token_printed = $false
  }
}

function New-Status {
  $Control = Get-ControlState
  $Lock = New-LockState
  $Resource = New-ResourceStatus
  $Alpha = Get-AlphaReadiness
  return [ordered]@{
    schema = "skybridge.local_supervisor_status.v1"
    worker_id = $WorkerId
    device_id_hash = $DeviceId
    repo = "skybridge-agent-hub"
    branch = Get-GitScalar -GitArgs @("rev-parse", "--abbrev-ref", "HEAD") -Fallback "unknown"
    commit = Get-GitScalar -GitArgs @("rev-parse", "--short", "HEAD") -Fallback "unknown"
    resident_enabled = $false
    execution_enabled = $false
    poll_enabled = $false
    resource_gate_status = $Resource.status
    active_tasks = $Lock.active_tasks
    stale_leases = $Lock.stale_leases
    runner_lock = $Lock.runner_lock
    open_review_hold = $Lock.open_review_hold
    no_next_execution_authorized = $true
    pause_preview_state = $Control.pause_after_current
    drain_preview_state = $Control.drain_after_current
    emergency_stop_preview_state = $Control.emergency_stop_requested
    alpha = $Alpha
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    token_printed = $false
  }
}

function New-Heartbeat {
  $Status = New-Status
  $Status.schema = "skybridge.local_supervisor_heartbeat.v1"
  return $Status
}

function New-ActionMatrix {
  return [ordered]@{
    schema = "skybridge.local_supervisor_action_matrix.v1"
    actions = @(
      [ordered]@{ id = "pause-preview"; preview_only = $true; writes_safe_state = $true; execution_enabled = $false; task_claim_enabled = $false; queue_apply_enabled = $false },
      [ordered]@{ id = "drain-preview"; preview_only = $true; writes_safe_state = $true; execution_enabled = $false; task_claim_enabled = $false; queue_apply_enabled = $false },
      [ordered]@{ id = "emergency-stop-preview"; preview_only = $true; writes_safe_state = $true; execution_enabled = $false; task_claim_enabled = $false; queue_apply_enabled = $false },
      [ordered]@{ id = "clear-preview-holds"; preview_only = $true; writes_safe_state = $true; execution_enabled = $false; task_claim_enabled = $false; queue_apply_enabled = $false }
    )
    token_printed = $false
  }
}

function New-SafeReport {
  $Heartbeat = New-Heartbeat
  $HeartbeatPath = Write-SafeJson -Path (Join-Path $StateDir "heartbeat.json") -Value $Heartbeat
  $Control = Get-ControlState
  $Resource = New-ResourceStatus
  $Report = [ordered]@{
    schema = "skybridge.desktop_resident_worker_goal_217_report.v1"
    resident_worker_shell_status = "implemented_safe_preview"
    desktop_panel_status = "implemented"
    tray_control_summary = "preview_only_safe_state"
    supervisor_heartbeat_path = $HeartbeatPath
    resource_gate_status = $Resource.status
    pause_preview_state = $Control.pause_after_current
    drain_preview_state = $Control.drain_after_current
    emergency_stop_preview_state = $Control.emergency_stop_requested
    execution_enabled = $false
    queue_apply_enabled = $false
    no_next_execution_authorized = $true
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    no_codex_execution = $true
    no_task_claim = $true
    no_raw_artifacts = $true
    ready_for_goal_218 = $true
    token_printed = $false
  }
  $JsonPath = Write-SafeJson -Path (Join-Path $ReportDir "goal-217-report.json") -Value $Report
  $MarkdownPath = Write-SafeMarkdown -Path (Join-Path $ReportDir "goal-217-report.md") -Lines @(
    "# Goal 217 Desktop Resident Worker Report",
    "",
    "- resident_worker_shell_status: implemented_safe_preview",
    "- desktop_panel_status: implemented",
    "- tray_control_summary: preview_only_safe_state",
    "- supervisor_heartbeat_path: $HeartbeatPath",
    "- execution_enabled: false",
    "- queue_apply_enabled: false",
    "- no_next_execution_authorized: true",
    "- active_tasks: 0",
    "- stale_leases: 0",
    "- runner_lock: none",
    "- no_codex_execution: true",
    "- no_task_claim: true",
    "- no_raw_artifacts: true",
    "- ready_for_goal_218: true",
    "- token_printed: false"
  )
  $Report.report_json_path = $JsonPath
  $Report.report_markdown_path = $MarkdownPath
  return $Report
}

switch ($Command) {
  "status" { $Result = New-Status }
  "heartbeat-once" {
    $Heartbeat = New-Heartbeat
    $Path = Write-SafeJson -Path (Join-Path $StateDir "heartbeat.json") -Value $Heartbeat
    $Heartbeat.heartbeat_path = $Path
    $Result = $Heartbeat
  }
  "heartbeat-preview" { $Result = New-Heartbeat }
  "lock-status" { $Result = New-LockState }
  "stale-lock-check" { $Result = New-LockState }
  "resource-status" { $Result = New-ResourceStatus }
  "resident-summary" { $Result = New-Status }
  "safe-report" { $Result = New-SafeReport }
  "pause-preview" { $Result = Set-ControlState -Action "pause-preview" }
  "drain-preview" { $Result = Set-ControlState -Action "drain-preview" }
  "emergency-stop-preview" { $Result = Set-ControlState -Action "emergency-stop-preview" }
  "clear-preview-holds" { $Result = Set-ControlState -Action "clear-preview-holds" }
  "control-state" { $Result = Get-ControlState }
  "action-matrix" { $Result = New-ActionMatrix }
  "evidence-summary" {
    $Alpha = Get-AlphaReadiness
    $Result = [ordered]@{
      schema = "skybridge.local_supervisor_evidence_summary.v1"
      alpha = $Alpha
      raw_evidence_displayed = $false
      token_printed = $false
    }
  }
  "no-execution-gate" {
    $Result = [ordered]@{
      schema = "skybridge.local_supervisor_no_execution_gate.v1"
      execution_enabled = $false
      poll_enabled = $false
      task_claim_enabled = $false
      queue_apply_enabled = $false
      codex_execution_enabled = $false
      arbitrary_shell_dispatch_enabled = $false
      no_next_execution_authorized = $true
      token_printed = $false
    }
  }
}

if ($Json) {
  ConvertTo-SafeJsonText -Value $Result
} else {
  $Result | Format-List
}
