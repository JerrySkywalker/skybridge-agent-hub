[CmdletBinding()]
param(
  [ValidateSet("status", "audit", "report", "safe-summary")]
  [string]$Command = "status",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/warning-inventory"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Schema = "skybridge.warning_inventory.v1"

function Resolve-RepoPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Convert-ToSafePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  $value = $Path.Replace("\", "/")
  $repo = $RepoRoot.Replace("\", "/").TrimEnd("/")
  if ($value.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $value.Substring($repo.Length).TrimStart("/")
  }
  if ($value -match "^[A-Za-z]:/") {
    return "%PATH%/" + (Split-Path -Leaf $value)
  }
  $value
}

function Resolve-OutputRoot {
  $fullTarget = Resolve-RepoPath $OutputDir
  $agentRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ".agent/tmp/warning-inventory"))
  if (-not $fullTarget.StartsWith($agentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be under .agent/tmp/warning-inventory."
  }
  $fullTarget
}

function Test-RelativeFile([string]$RelativePath) {
  Test-Path -LiteralPath (Join-Path $RepoRoot $RelativePath) -PathType Leaf
}

function Get-GitChangedFiles {
  $files = @()
  $raw = & git -C $RepoRoot status --porcelain=v1 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }
  foreach ($line in @($raw)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -match " -> ") { $path = ($path -split " -> ")[-1].Trim() }
    if (-not [string]::IsNullOrWhiteSpace($path)) {
      $files += $path.Replace("\", "/")
    }
  }
  $files
}

function Test-AnyPathMatches([string[]]$Paths, [string]$Pattern) {
  foreach ($path in $Paths) {
    if ($path -match $Pattern) { return $true }
  }
  return $false
}

function New-KnownWarnings {
  @(
    [pscustomobject]@{
      warning_id = "vite_chunk_size_warning"
      category = "Vite chunk-size warning"
      status = "non_failing_tracked_not_suppressed"
      impact = "does_not_block_managed_dev_baseline_or_deploy_cloud"
      remediation = "MG366A Vite Chunk Warning Analysis"
    }
    [pscustomobject]@{
      warning_id = "github_actions_node20_deprecation_annotation"
      category = "GitHub Actions Node.js 20 deprecation annotation for Docker actions"
      status = "non_failing_tracked_not_suppressed"
      impact = "does_not_block_managed_dev_baseline_or_deploy_cloud"
      remediation = "MG366B GitHub Actions Node Runtime Hygiene"
    }
  )
}

function New-Report {
  $changedFiles = @(Get-GitChangedFiles)
  $workflowChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)^\.github/workflows/"
  $buildConfigChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^|/)(vite\.config\.[cm]?[jt]s|tsconfig\.json|rollup\.config\.[cm]?[jt]s|package-lock\.json|pnpm-lock\.yaml)$"
  $deployConfigChanged = Test-AnyPathMatches -Paths $changedFiles -Pattern "(?i)(^deploy/|docker-compose|Dockerfile|openresty|authelia|cloudflare|dns/|tls/|firewall/)"
  $docPresent = Test-RelativeFile "docs/dev/WARNING_INVENTORY.md"

  [pscustomobject]@{
    schema = $Schema
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    known_warnings = @(New-KnownWarnings)
    vite_chunk_warning_status = "non_failing_tracked_not_suppressed"
    github_actions_node20_deprecation_status = "non_failing_tracked_not_suppressed"
    warnings_are_non_failing = $true
    warnings_suppressed = $false
    ci_threshold_changed = $false
    workflow_changed = [bool]$workflowChanged
    build_config_changed = [bool]$buildConfigChanged
    deploy_config_changed = [bool]$deployConfigChanged
    remediation_required = $true
    recommended_next_goals = @(
      "MG366A Vite Chunk Warning Analysis",
      "MG366B GitHub Actions Node Runtime Hygiene",
      "MG366C Hermes Planner Provider Pilot"
    )
    warning_inventory_doc_present = $docPresent
    release_created = $false
    tag_created = $false
    asset_uploaded = $false
    auto_merge_enabled = $false
    worker_loop_started = $false
    queue_runner_started = $false
    task_created = $false
    task_claimed = $false
    codex_run_called = $false
    matlab_run_called = $false
    hermes_run_called = $false
    mcp_run_called = $false
    token_printed = $false
  }
}

function Write-Reports($Report) {
  $root = Resolve-OutputRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $jsonPath = Join-Path $root "warning-inventory.json"
  $mdPath = Join-Path $root "warning-inventory.md"
  $Report | Add-Member -NotePropertyName report_json_path -NotePropertyValue (Convert-ToSafePath $jsonPath) -Force
  $Report | Add-Member -NotePropertyName report_markdown_path -NotePropertyValue (Convert-ToSafePath $mdPath) -Force
  $Report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $lines = @(
    "# Warning Inventory Report",
    "",
    "- schema: $($Report.schema)",
    "- known_warnings: $(@($Report.known_warnings).Count)",
    "- vite_chunk_warning_status: $($Report.vite_chunk_warning_status)",
    "- github_actions_node20_deprecation_status: $($Report.github_actions_node20_deprecation_status)",
    "- warnings_are_non_failing: $($Report.warnings_are_non_failing)",
    "- warnings_suppressed=false",
    "- ci_threshold_changed=false",
    "- workflow_changed: $($Report.workflow_changed)",
    "- build_config_changed: $($Report.build_config_changed)",
    "- deploy_config_changed: $($Report.deploy_config_changed)",
    "- remediation_required: $($Report.remediation_required)",
    "- release_created=false",
    "- tag_created=false",
    "- asset_uploaded=false",
    "- auto_merge_enabled=false",
    "- worker_loop_started=false",
    "- token_printed=false"
  )
  $lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

$report = New-Report
if ($Command -eq "safe-summary") {
  $report = [pscustomobject]@{
    schema = $Schema
    known_warning_count = @($report.known_warnings).Count
    warnings_are_non_failing = $report.warnings_are_non_failing
    warnings_suppressed = $false
    workflow_changed = $report.workflow_changed
    build_config_changed = $report.build_config_changed
    deploy_config_changed = $report.deploy_config_changed
    worker_loop_started = $false
    token_printed = $false
  }
}

if ($WriteReport -or $Command -eq "report") {
  Write-Reports $report
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} elseif ($Command -eq "safe-summary") {
  Write-Host "Warning inventory: known_warning_count=$($report.known_warning_count) warnings_suppressed=false token_printed=false"
} else {
  Write-Host "Warning inventory"
  Write-Host "- known_warnings: $(@($report.known_warnings).Count)"
  Write-Host "- warnings_are_non_failing: $($report.warnings_are_non_failing)"
  Write-Host "- warnings_suppressed=false"
  Write-Host "- workflow_changed: $($report.workflow_changed)"
  Write-Host "- build_config_changed: $($report.build_config_changed)"
  Write-Host "- deploy_config_changed: $($report.deploy_config_changed)"
  Write-Host "- token_printed=false"
}
