[CmdletBinding()]
param(
  [switch]$Preview,
  [switch]$ApplyLocal,
  [switch]$CreateDraftPR,
  [switch]$ObserveCI,
  [switch]$Fixture,
  [switch]$Json,
  [switch]$WriteReport,
  [string]$BranchName = "codex/mega-357-managed-dev-pr-pilot-fixture",
  [string]$Confirm = "",
  [string]$OutputDir = ".agent/tmp/managed-dev-pilot"
)

$ErrorActionPreference = "Stop"

if (-not $Preview -and -not $ApplyLocal -and -not $CreateDraftPR -and -not $ObserveCI) { $Preview = $true }
$fixtureBranch = "codex/mega-357-managed-dev-pr-pilot-fixture"
if (-not $Fixture -and -not $ApplyLocal -and -not $CreateDraftPR -and -not $ObserveCI -and $BranchName -eq $fixtureBranch) {
  $Fixture = $true
}

$command = "preview"
if ($ApplyLocal -and $Fixture) {
  $command = "apply-fixture"
} elseif ($ApplyLocal) {
  $command = "apply-local"
} elseif ($CreateDraftPR) {
  $command = "create-draft-pr"
} elseif ($ObserveCI) {
  $command = "ci-status"
}

$args = @(
  "-Command", $command,
  "-OutputDir", $OutputDir,
  "-BranchName", $BranchName,
  "-Json"
)
if ($Fixture) { $args += "-Fixture" } else { $args += "-Local" }
if ($WriteReport) { $args += "-WriteReport" }
if ($ObserveCI) { $args += "-ObserveCI" }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-managed-dev-pilot.ps1") @args
if ($LASTEXITCODE -ne 0) { throw "skybridge-managed-dev-pilot.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

$checklist = [pscustomobject]@{
  schema = "skybridge.managed_dev_pilot_manual_test.v1"
  milestone = "M7: Managed Development PR Pilot"
  mode = $result.mode
  command = $command
  branch_name = $result.branch_name
  files_changed = $result.files_changed
  changed_files = @($result.changed_files)
  local_validations_run = $result.local_validations_run
  local_validations_passed = $result.local_validations_passed
  draft_pr_created = $result.draft_pr_created
  pr_number = $result.pr_number
  pr_url_safe = $result.pr_url_safe
  pr_ci_status = $result.pr_ci_status
  held_for_human_review = $result.held_for_human_review
  auto_merge_enabled = $result.auto_merge_enabled
  merge_performed = $result.merge_performed
  release_created = $result.release_created
  tag_created = $result.tag_created
  asset_uploaded = $result.asset_uploaded
  worker_loop_started = $result.worker_loop_started
  blockers = @($result.blockers)
  warnings = @($result.warnings)
  token_printed = $false
  result = $result
}

if ($Json) {
  $checklist | ConvertTo-Json -Depth 90
} else {
  Write-Host "M7 Manual Test Checklist:"
  Write-Host "- mode: $($checklist.mode)"
  Write-Host "- command: $($checklist.command)"
  Write-Host "- branch: $($checklist.branch_name)"
  Write-Host "- changed files: $($checklist.files_changed)"
  Write-Host "- draft PR created: $($checklist.draft_pr_created)"
  Write-Host "- PR CI status: $($checklist.pr_ci_status)"
  Write-Host "- held for human review: $($checklist.held_for_human_review)"
  Write-Host "- auto_merge_enabled=false"
  Write-Host "- merge_performed=false"
  Write-Host "- release_created=false"
  Write-Host "- tag_created=false"
  Write-Host "- asset_uploaded=false"
  Write-Host "- worker_loop_started=false"
  Write-Host "- token_printed=false"
}
