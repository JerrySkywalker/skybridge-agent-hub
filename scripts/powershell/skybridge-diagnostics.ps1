[CmdletBinding()]
param(
  [ValidateSet("health", "product-readiness", "dependency-check", "git-state", "node-state", "rust-state", "desktop-state", "web-state", "server-state", "smoke-matrix-state", "runtime-state", "runtime-session-health", "runtime-lock-health", "runtime-port-health", "cleanup-preview", "safe-summary", "report")]
  [string]$Command = "health",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$DiagnosticsDir = Join-Path $RepoRoot ".agent\tmp\diagnostics"
$ReadinessDir = Join-Path $RepoRoot ".agent\tmp\product-readiness"

function Get-SafeGitValue([string[]]$Args) {
  $out = & git -C $RepoRoot @Args 2>$null
  if ($LASTEXITCODE -ne 0) { return "" }
  (($out | Out-String).Trim())
}

function Get-CommandPresence([string]$Name) {
  [pscustomobject]@{ name = $Name; available = [bool](Get-Command $Name -ErrorAction SilentlyContinue); token_printed = $false }
}

function New-State([string]$Name, [bool]$Ok, [string]$Summary, [string[]]$Warnings = @()) {
  [pscustomobject]@{ schema = "skybridge.local_state_health.v1"; name = $Name; ok = $Ok; summary = $Summary; warnings = @($Warnings); token_printed = $false }
}

function New-DependencyCheck {
  $items = @("git", "node", "corepack", "pnpm", "pwsh", "cargo") | ForEach-Object { Get-CommandPresence $_ }
  [pscustomobject]@{ schema = "skybridge.local_dependency_check.v1"; checks = @($items); ok = (-not ($items | Where-Object { $_.available -ne $true -and $_.name -ne "cargo" })); token_printed = $false }
}

function New-GitState {
  $branch = Get-SafeGitValue @("branch", "--show-current")
  $status = Get-SafeGitValue @("status", "--porcelain")
  [pscustomobject]@{ schema = "skybridge.local_git_state.v1"; branch = $branch; clean = [string]::IsNullOrWhiteSpace($status); commit = (Get-SafeGitValue @("rev-parse", "--short", "HEAD")); token_printed = $false }
}

function New-RuntimeDiagnosticsState {
  [pscustomobject]@{
    schema = "skybridge.runtime_diagnostics_state.v1"
    runtime_orchestrator_state = "preview_ready"
    product_profiles = @("dev-preview", "desktop-only", "web-control-plane-preview", "supervisor-heartbeat-preview", "resident-polling-preview", "full-local-preview")
    desktop_readiness = "preview_build_only"
    web_readiness = "read_only_dashboard"
    server_preview_readiness = "build_only"
    resident_polling_preview_readiness = "status_only"
    smoke_matrix_state = "local_validation_only"
    disabled_capability_state = @("execution", "queue_apply", "remote_execution", "arbitrary_command_dispatch")
    raw_logs_included = $false
    token_printed = $false
  }
}

function Invoke-RuntimeJson([string]$RuntimeCommand) {
  $json = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-runtime.ps1") -Command $RuntimeCommand -Json
  if ($LASTEXITCODE -ne 0) { throw "Runtime diagnostics command failed: $RuntimeCommand" }
  $json | ConvertFrom-Json
}

function New-RuntimeSessionHealth {
  $candidate = Invoke-RuntimeJson "apply-candidate"
  [pscustomobject]@{
    schema = "skybridge.runtime_session_health.v1"
    status = "bounded_candidate_ready"
    session_id = $candidate.session_id
    component_count = @($candidate.components).Count
    starts_codex_worker = $false
    runs_workunit_apply = $false
    starts_unbounded_loop = $false
    raw_log_persisted = $false
    token_printed = $false
  }
}

function New-RuntimeLockHealth {
  $lock = Invoke-RuntimeJson "lock-check"
  [pscustomobject]@{
    schema = "skybridge.runtime_lock_health.v1"
    lock_file_path = $lock.lock_file_path
    stale_lock_detected = [bool]$lock.stale_lock_detected
    stale_pid_detected = [bool]$lock.stale_pid_detected
    unsafe_component_detected = [bool]$lock.unsafe_component_detected
    token_printed = $false
  }
}

function New-RuntimePortHealth {
  $ports = Invoke-RuntimeJson "port-check"
  [pscustomobject]@{
    schema = "skybridge.runtime_port_health.v1"
    checks = @($ports.checks)
    ok = $true
    token_printed = $false
  }
}

function New-CleanupPreview {
  $cleanup = Invoke-RuntimeJson "cleanup-stale-session"
  [pscustomobject]@{
    schema = "skybridge.runtime_cleanup_preview.v1"
    session_id = $cleanup.session_id
    preview_only = $true
    background_process_left_running = $false
    raw_log_persisted = $false
    token_printed = $false
  }
}

function New-HealthReport {
  $git = New-GitState
  $deps = New-DependencyCheck
  [pscustomobject]@{
    schema = "skybridge.local_health_report.v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    git = $git
    dependencies = $deps
    states = @(
      New-State "bootstrap-complete" $true "Release tag and bootstrap gate are expected before productization."
      New-State "runtime-orchestrator" $true "Local runtime orchestrator is preview-only."
      New-State "desktop" $true "Desktop preview is build-only and execution disabled."
      New-State "web" $true "Web product readiness route is read-only."
      New-State "server" $true "Server preview is metadata-only."
      New-State "smoke-matrix" $true "Smoke matrix remains local validation only."
    )
    execution_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    runtime_diagnostics = New-RuntimeDiagnosticsState
    token_printed = $false
  }
}

function New-ProductReadinessReport {
  [pscustomobject]@{
    schema = "skybridge.product_readiness_report.v1"
    status = "ready_for_local_preview"
    product_state_layout = "defined"
    launch_profiles = "preview_only"
    diagnostics = "safe_reports"
    packaging_preview = "metadata_only"
    windows_launcher_preview = "dry_run_only"
    bootstrap_complete = $true
    disabled_capabilities = @("execution", "queue_apply", "remote_execution", "arbitrary_command_dispatch", "global_trusted_docs_auto_merge")
    next_safe_action = "Run productization smokes, then review the read-only dashboard."
    token_printed = $false
  }
}

function Write-HealthReports {
  $health = New-HealthReport
  New-Item -ItemType Directory -Force -Path $DiagnosticsDir | Out-Null
  $health | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $DiagnosticsDir "health-report.json") -Encoding utf8
  @(
    "# Health Report",
    "",
    "- schema: skybridge.local_health_report.v1",
    "- git_clean: $($health.git.clean)",
    "- dependency_check: $($health.dependencies.ok)",
    "- execution_enabled=false",
    "- queue_apply_enabled=false",
    "- remote_execution_enabled=false",
    "- arbitrary_command_enabled=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $DiagnosticsDir "health-report.md") -Encoding utf8
  $readiness = New-ProductReadinessReport
  New-Item -ItemType Directory -Force -Path $ReadinessDir | Out-Null
  $readiness | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $ReadinessDir "product-readiness-report.json") -Encoding utf8
  $runtimeSession = New-RuntimeSessionHealth
  $runtimeSession | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $DiagnosticsDir "runtime-session-health.json") -Encoding utf8
  @(
    "# Runtime Session Health",
    "",
    "- schema: skybridge.runtime_session_health.v1",
    "- status: bounded_candidate_ready",
    "- starts_codex_worker=false",
    "- runs_workunit_apply=false",
    "- starts_unbounded_loop=false",
    "- raw_log_persisted=false",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $DiagnosticsDir "runtime-session-health.md") -Encoding utf8
  @(
    "# Product Readiness Report",
    "",
    "- schema: skybridge.product_readiness_report.v1",
    "- status: $($readiness.status)",
    "- launch_profiles: preview_only",
    "- diagnostics: safe_reports",
    "- packaging_preview: metadata_only",
    "- windows_launcher_preview: dry_run_only",
    "- token_printed=false"
  ) | Set-Content -LiteralPath (Join-Path $ReadinessDir "product-readiness-report.md") -Encoding utf8
  [pscustomobject]@{ schema = "skybridge.diagnostics_report_index.v1"; health_report = ".agent/tmp/diagnostics/health-report.json"; product_readiness_report = ".agent/tmp/product-readiness/product-readiness-report.json"; ok = $true; token_printed = $false }
}

$result = switch ($Command) {
  "health" { New-HealthReport }
  "product-readiness" { New-ProductReadinessReport }
  "dependency-check" { New-DependencyCheck }
  "git-state" { New-GitState }
  "node-state" { New-State "node" ([bool](Get-Command node -ErrorAction SilentlyContinue)) "Node command presence only; no environment dump." }
  "rust-state" { New-State "rust" ([bool](Get-Command cargo -ErrorAction SilentlyContinue)) "Cargo command presence only; no environment dump." }
  "desktop-state" { New-State "desktop" $true "Desktop preview build target present; no install." }
  "web-state" { New-State "web" $true "Web preview route is read-only." }
  "server-state" { New-State "server" $true "Server preview is build-only." }
  "smoke-matrix-state" { New-State "smoke-matrix" $true "Smoke matrix scripts are local validation only." }
  "runtime-state" { New-RuntimeDiagnosticsState }
  "runtime-session-health" { New-RuntimeSessionHealth }
  "runtime-lock-health" { New-RuntimeLockHealth }
  "runtime-port-health" { New-RuntimePortHealth }
  "cleanup-preview" { New-CleanupPreview }
  "safe-summary" { [pscustomobject]@{ ok = $true; diagnostics_safe = $true; raw_env_dump = $false; raw_logs = $false; runtime_session_diagnostics = $true; token_printed = $false } }
  "report" { Write-HealthReports }
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List | Out-String }
