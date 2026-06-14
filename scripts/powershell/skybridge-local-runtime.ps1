[CmdletBinding()]
param(
  [ValidateSet("status", "plan", "start-preview", "stop-preview", "restart-preview", "health", "pid-plan", "profile-plan", "safe-summary", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReportDir = Join-Path $RepoRoot ".agent\tmp\local-runtime"

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
  $plan | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "runtime-plan.json") -Encoding utf8
  $health | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "runtime-health-report.json") -Encoding utf8
  $report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDir "local-runtime-report.json") -Encoding utf8
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
  "safe-summary" { [pscustomobject]@{ ok = $true; dry_run = $true; starts_codex_worker = $false; starts_unbounded_loop = $false; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "report" { Write-RuntimeReports }
}

if ($Json) { $result | ConvertTo-Json -Depth 30 } else { $result | Format-List | Out-String }
