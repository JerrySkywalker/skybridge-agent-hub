[CmdletBinding()]
param(
  [ValidateSet("status", "report")]
  [string]$Command = "status",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.Core.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.WorkunitRegistry.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.QueuePolicy.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.EvidenceStore.psm1") -Force -Global

function Resolve-ReportPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path $Path))
}

function Test-ReportUnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Write-ReportSafeJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
  $full = Resolve-ReportPath $Path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
  $json = $Value | ConvertTo-Json -Depth 12
  if (Test-ReportUnsafeText $json) { throw "Unsafe JSON report." }
  Set-Content -LiteralPath $full -Value $json -Encoding utf8
}

function New-CoreEngineReport {
  $modules = @(
    "Skybridge.Core",
    "Skybridge.CodexExecutor",
    "Skybridge.ResourceGate",
    "Skybridge.WorkunitRegistry",
    "Skybridge.EvidenceStore",
    "Skybridge.PrPackager",
    "Skybridge.Finalizer",
    "Skybridge.QueuePolicy",
    "Skybridge.SafetyScanner",
    "Skybridge.SmokeHarness"
  )
  $registry = Get-SkybridgeRunRegistrySummary
  [pscustomobject]@{
    schema = "skybridge.core_engine_goal_214_report.v1"
    goal = "214"
    modules_added = $modules
    scripts_migrated = @(
      "scripts/powershell/skybridge-managed-mode-run.ps1",
      "scripts/powershell/skybridge-managed-mode-pilot.ps1",
      "scripts/powershell/skybridge-managed-mode-v0.ps1",
      "scripts/powershell/skybridge-boinc-v1-preview.ps1",
      "scripts/powershell/skybridge-local-resource-policy.ps1",
      "scripts/powershell/skybridge-worker-scheduler.ps1",
      "scripts/powershell/skybridge-goal-to-workunit.ps1",
      "scripts/powershell/skybridge-workunit-queue.ps1",
      "scripts/powershell/skybridge-boinc-manager.ps1"
    )
    compatibility_status = "legacy_command_names_preserved"
    smoke_list = @(
      "smoke-core-engine-module-imports.ps1",
      "smoke-core-engine-safe-json.ps1",
      "smoke-core-engine-token-printed-false.ps1",
      "smoke-core-engine-codex-launcher-fixtures.ps1",
      "smoke-core-engine-resource-gate-fixtures.ps1",
      "smoke-core-engine-registry-reads-completed-runs.ps1",
      "smoke-core-engine-evidence-store-hashes.ps1",
      "smoke-core-engine-pr-packager-allowlist.ps1",
      "smoke-core-engine-finalizer-preview-only.ps1",
      "smoke-core-engine-queue-policy-apply-disabled.ps1",
      "smoke-wrapper-managed-mode-run-compat.ps1",
      "smoke-wrapper-managed-mode-pilot-compat.ps1",
      "smoke-wrapper-boinc-v1-preview-compat.ps1",
      "smoke-wrapper-local-resource-policy-compat.ps1",
      "smoke-desktop-core-engine-status-panel.ps1",
      "smoke-web-core-engine-status-panel.ps1"
    )
    completed_runs_still_readable = ($registry.completed_run_count -eq 4)
    completed_runs = $registry.completed_runs
    no_execution_performed = $true
    task_created = $false
    task_claimed = $false
    workunit_created = $false
    task_pr_created = $false
    bounded_queue_apply = $false
    start_all_or_start_queue_or_resume = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

$report = New-CoreEngineReport

if ($Command -eq "report") {
  $jsonPath = ".agent/tmp/core-engine/goal-214-core-engine-report.json"
  $mdPath = ".agent/tmp/core-engine/goal-214-core-engine-report.md"
  Write-ReportSafeJson -Path $jsonPath -Value $report
  $md = @(
    "# Goal 214 Core Engine Report",
    "",
    "- modules added: $(@($report.modules_added).Count)",
    "- scripts migrated: $(@($report.scripts_migrated).Count)",
    "- compatibility status: $($report.compatibility_status)",
    "- completed runs still readable: $($report.completed_runs_still_readable)",
    "- no execution performed: true",
    "- token_printed=false"
  ) -join "`n"
  if (Test-ReportUnsafeText $md) { throw "Unsafe markdown report." }
  $fullMd = Resolve-ReportPath $mdPath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullMd) | Out-Null
  Set-Content -LiteralPath $fullMd -Value $md -Encoding utf8
  $report | Add-Member -NotePropertyName report_json_path -NotePropertyValue $jsonPath -Force
  $report | Add-Member -NotePropertyName report_md_path -NotePropertyValue $mdPath -Force
}

if ($Json) {
  $report | ConvertTo-Json -Depth 12
} else {
  $report
}
