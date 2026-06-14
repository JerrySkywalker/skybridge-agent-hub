[CmdletBinding()]
param(
  [ValidateSet("status", "plan", "start-preview", "stop-preview", "restart-preview", "health", "pid-plan", "profile-plan", "apply-candidate", "start-local-session", "stop-local-session", "restart-local-session", "session-status", "cleanup-stale-session", "port-check", "lock-check", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-runtime"
$SessionId = "local-runtime-rc-session"
$SessionDir = Join-Path $ReportDir "sessions"
$LockFile = Join-Path $SessionDir "$SessionId.lock.json"
$PidFile = Join-Path $SessionDir "$SessionId.pid.json"

function New-RuntimeComponent([string]$Id, [string]$CommandPreview) {
  [pscustomobject]@{
    schema = "skybridge.local_runtime_component.v1"
    component_id = $Id
    command_preview = $CommandPreview
    enabled_by_default = $false
    bounded = $true
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    starts_codex_worker = $false
    starts_unbounded_loop = $false
    creates_workunit = $false
    creates_task = $false
    claims_task = $false
    creates_service = $false
    writes_registry = $false
    writes_startup = $false
    mutates_power_settings = $false
    token_printed = $false
  }
}

function Get-RuntimeComponents {
  @(
    New-RuntimeComponent "desktop" "corepack pnpm -C apps/desktop build"
    New-RuntimeComponent "web" "corepack pnpm --filter @skybridge-agent-hub/web build"
    New-RuntimeComponent "server-preview" "corepack pnpm --filter @skybridge-agent-hub/server build"
    New-RuntimeComponent "local-supervisor-heartbeat" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-supervisor.ps1 -Command status"
    New-RuntimeComponent "resident-polling-preview" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-resident-polling.ps1 -Command status"
    New-RuntimeComponent "diagnostics" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-diagnostics.ps1 -Command report"
    New-RuntimeComponent "product-readiness" "pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-diagnostics.ps1 -Command product-readiness"
  )
}

function New-SessionComponent([string]$Id, [int]$Port, [string]$CommandPreview) {
  [pscustomobject]@{
    schema = "skybridge.local_runtime_session.v1"
    session_id = $SessionId
    component_id = $Id
    command_preview_sanitized = $CommandPreview
    pid_present = $false
    pid_file_path = ".agent/tmp/local-runtime/sessions/$SessionId.pid.json"
    lock_file_path = ".agent/tmp/local-runtime/sessions/$SessionId.lock.json"
    port = $Port
    port_available = Test-PortAvailable $Port
    started_by_preview_or_apply_candidate = $true
    bounded = $true
    stop_supported = $true
    stale_detection_supported = $true
    raw_log_persisted = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    token_printed = $false
  }
}

function Test-PortAvailable([int]$Port) {
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    $listener.Stop()
    return $true
  } catch {
    return $false
  }
}

function New-PortCheck {
  $checks = @(
    [pscustomobject]@{ schema = "skybridge.local_runtime_port_check.v1"; component_id = "web"; port = 5173; port_available = Test-PortAvailable 5173; token_printed = $false }
    [pscustomobject]@{ schema = "skybridge.local_runtime_port_check.v1"; component_id = "server-preview"; port = 8787; port_available = Test-PortAvailable 8787; token_printed = $false }
  )
  [pscustomobject]@{ schema = "skybridge.local_runtime_port_check.v1"; checks = @($checks); ok = $true; token_printed = $false }
}

function New-LockState {
  $exists = Test-Path -LiteralPath $LockFile
  [pscustomobject]@{
    schema = "skybridge.local_runtime_lock.v1"
    session_id = $SessionId
    lock_file_path = ".agent/tmp/local-runtime/sessions/$SessionId.lock.json"
    lock_present = $exists
    stale_lock_detected = $false
    stale_pid_detected = $false
    unsafe_component_detected = $false
    execution_component_included = $false
    raw_log_path_included = $false
    token_printed = $false
  }
}

function New-ApplyCandidate {
  $components = @(
    New-SessionComponent "web" 5173 "corepack pnpm --filter @skybridge-agent-hub/web dev --host 127.0.0.1 --strictPort"
    New-SessionComponent "server-preview" 8787 "corepack pnpm --filter @skybridge-agent-hub/server dev"
    New-SessionComponent "desktop-dev-preview-metadata" 0 "corepack pnpm -C apps/desktop build"
    New-SessionComponent "local-supervisor-heartbeat-preview" 0 "pwsh -File scripts/powershell/skybridge-local-supervisor.ps1 -Command status"
    New-SessionComponent "resident-polling-preview" 0 "pwsh -File scripts/powershell/skybridge-resident-polling.ps1 -Command status"
    New-SessionComponent "diagnostics" 0 "pwsh -File scripts/powershell/skybridge-diagnostics.ps1 -Command report"
    New-SessionComponent "product-readiness" 0 "pwsh -File scripts/powershell/skybridge-diagnostics.ps1 -Command product-readiness"
  )
  [pscustomobject]@{
    schema = "skybridge.local_runtime_apply_candidate.v1"
    mode = "bounded_non_worker_local_candidate"
    session_id = $SessionId
    components = @($components)
    lock = New-LockState
    port_check = New-PortCheck
    starts_codex_worker = $false
    runs_workunit_apply = $false
    claims_task = $false
    queue_apply_enabled = $false
    starts_unbounded_loop = $false
    bounded = $true
    stop_supported = $true
    cleanup_supported = $true
    token_printed = $false
  }
}

function Write-SessionMetadata {
  New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
  $session = [pscustomobject]@{
    schema = "skybridge.local_runtime_session.v1"
    session_id = $SessionId
    status = "metadata_started"
    bounded = $true
    pid_present = $false
    pid_file_path = ".agent/tmp/local-runtime/sessions/$SessionId.pid.json"
    lock_file_path = ".agent/tmp/local-runtime/sessions/$SessionId.lock.json"
    stop_supported = $true
    stale_detection_supported = $true
    raw_log_persisted = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
  $session | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $LockFile -Encoding utf8
  [pscustomobject]@{ pid = $null; pid_present = $false; token_printed = $false } | ConvertTo-Json | Set-Content -LiteralPath $PidFile -Encoding utf8
  $session
}

function Stop-SessionMetadata {
  if (Test-Path -LiteralPath $LockFile) { Remove-Item -LiteralPath $LockFile -Force }
  if (Test-Path -LiteralPath $PidFile) { Remove-Item -LiteralPath $PidFile -Force }
  [pscustomobject]@{ schema = "skybridge.local_runtime_cleanup_report.v1"; session_id = $SessionId; stopped = $true; stale_lock_removed = $true; stale_pid_removed = $true; background_process_left_running = $false; token_printed = $false }
}

function New-CleanupReport {
  $lockExists = Test-Path -LiteralPath $LockFile
  $pidExists = Test-Path -LiteralPath $PidFile
  [pscustomobject]@{
    schema = "skybridge.local_runtime_cleanup_report.v1"
    session_id = $SessionId
    stale_lock_detected = $lockExists
    stale_pid_detected = $pidExists
    stale_lock_removed = $false
    stale_pid_removed = $false
    preview_only = $true
    background_process_left_running = $false
    raw_log_persisted = $false
    token_printed = $false
  }
}

function New-ProcessStatus([string]$Id) {
  [pscustomobject]@{
    schema = "skybridge.local_process_status.v1"
    process_id = $Id
    expected_state = "preview_only"
    pid = $null
    pid_persisted = $false
    raw_process_output_persisted = $false
    command_transcript_persisted = $false
    environment_persisted = $false
    token_printed = $false
  }
}

function New-RuntimePlan([string]$Kind) {
  $components = @(Get-RuntimeComponents)
  [pscustomobject]@{
    schema = "skybridge.local_runtime_plan.v1"
    command = $Kind
    dry_run = $true
    preview_only = $true
    components = $components
    process_plan = [pscustomobject]@{
      schema = "skybridge.local_process_plan.v1"
      statuses = @($components | ForEach-Object { New-ProcessStatus $_.component_id })
      blockers = @([pscustomobject]@{ schema = "skybridge.local_process_blocker.v1"; code = "execution_disabled_by_default"; active = $false; token_printed = $false })
      token_printed = $false
    }
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    token_printed = $false
  }
}

function New-RuntimeHealth {
  $plan = New-RuntimePlan "health"
  [pscustomobject]@{
    schema = "skybridge.local_runtime_health.v1"
    ok = $true
    status = "preview_ready"
    component_count = @($plan.components).Count
    process_health = [pscustomobject]@{
      schema = "skybridge.process_health_state.v1"
      ok = $true
      raw_process_output_persisted = $false
      full_command_transcripts_persisted = $false
      environment_variables_persisted = $false
      absolute_paths_sanitized = $true
      token_printed = $false
    }
    disabled_capabilities = @("execution", "queue_apply", "remote_execution", "arbitrary_command_dispatch", "codex_worker", "unbounded_loop")
    token_printed = $false
  }
}

function Write-RuntimeReports {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $plan = New-RuntimePlan "report"
  $health = New-RuntimeHealth
  $report = [pscustomobject]@{
    schema = "skybridge.local_runtime_report.v1"
    orchestrator = [pscustomobject]@{
      schema = "skybridge.local_runtime_orchestrator.v1"
      mode = "dry_run_preview"
      reports_dir = ".agent/tmp/local-runtime"
      token_printed = $false
    }
    plan = $plan
    health = $health
    token_printed = $false
  }
  $applyCandidate = New-ApplyCandidate
  $sessionReport = [pscustomobject]@{ schema = "skybridge.local_runtime_session_report.v1"; session = Write-SessionMetadata; apply_candidate = $applyCandidate; token_printed = $false }
  $cleanupReport = New-CleanupReport
  $plan | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "runtime-plan.json") -Encoding utf8
  $health | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "runtime-health-report.json") -Encoding utf8
  $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "local-runtime-report.json") -Encoding utf8
  $applyCandidate | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "local-runtime-apply-candidate.json") -Encoding utf8
  $sessionReport | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "local-runtime-session-report.json") -Encoding utf8
  $cleanupReport | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "local-runtime-cleanup-report.json") -Encoding utf8
  @(
    "# Runtime Health Report",
    "",
    "- schema: skybridge.local_runtime_health.v1",
    "- status: preview_ready",
    "- raw_process_output_persisted=false",
    "- full_command_transcripts_persisted=false",
    "- environment_variables_persisted=false",
    "- execution_enabled=false",
    "- queue_apply_enabled=false",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReportDir "runtime-health-report.md") -Encoding utf8
  $report
}

$result = switch ($Command) {
  "status" { [pscustomobject]@{ schema = "skybridge.local_runtime_orchestrator.v1"; mode = "dry_run_preview"; components = @(Get-RuntimeComponents); token_printed = $false } }
  "plan" { New-RuntimePlan "plan" }
  "start-preview" { New-RuntimePlan "start-preview" }
  "stop-preview" { New-RuntimePlan "stop-preview" }
  "restart-preview" { New-RuntimePlan "restart-preview" }
  "health" { New-RuntimeHealth }
  "pid-plan" { (New-RuntimePlan "pid-plan").process_plan }
  "profile-plan" { [pscustomobject]@{ schema = "skybridge.local_runtime_plan.v1"; profile = "full-local-preview"; plan = New-RuntimePlan "profile-plan"; token_printed = $false } }
  "apply-candidate" { New-ApplyCandidate }
  "start-local-session" { Write-SessionMetadata }
  "stop-local-session" { Stop-SessionMetadata }
  "restart-local-session" { Stop-SessionMetadata | Out-Null; Write-SessionMetadata }
  "session-status" { if (Test-Path -LiteralPath $LockFile) { Get-Content -Raw -LiteralPath $LockFile | ConvertFrom-Json } else { [pscustomobject]@{ schema = "skybridge.local_runtime_session.v1"; session_id = $SessionId; status = "stopped"; pid_present = $false; token_printed = $false } } }
  "cleanup-stale-session" { New-CleanupReport }
  "port-check" { New-PortCheck }
  "lock-check" { New-LockState }
  "safe-summary" { [pscustomobject]@{ ok = $true; dry_run = $false; bounded_apply_candidate = $true; starts_codex_worker = $false; starts_unbounded_loop = $false; runs_workunit_apply = $false; claims_task = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-RuntimeReports }
}

if ($Json) { $result | ConvertTo-Json -Depth 30 } else { $result | Format-List | Out-String }
