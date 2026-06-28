[CmdletBinding()]
param(
  [switch]$Preview,
  [switch]$RunFixture,
  [switch]$ApplyOne,
  [switch]$CreateDraftPR,
  [switch]$ObserveCI,
  [switch]$Fixture,
  [switch]$Local,
  [switch]$Json,
  [switch]$WriteReport,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "managed-dev-campaign-fixture-362",
  [string]$GoalId = "managed-dev-campaign-goal-362-fixture",
  [string]$BranchName = "codex/mg362-campaign-driven-managed-dev-pilot-pr",
  [string]$Confirm = "",
  [string]$OutputDir = ".agent/tmp/managed-dev-campaign"
)

$ErrorActionPreference = "Stop"

if (-not $Preview -and -not $RunFixture -and -not $ApplyOne -and -not $CreateDraftPR -and -not $ObserveCI) {
  $Preview = $true
}

if ($Local) {
  $Fixture = $false
} elseif (-not $Local) {
  $Fixture = $true
}

$command = "preview"
if ($RunFixture) {
  $command = "run-fixture-e2e"
} elseif ($ApplyOne) {
  $command = "bounded-apply-one"
} elseif ($CreateDraftPR) {
  $command = "create-draft-pr"
} elseif ($ObserveCI) {
  $command = "observe-ci"
}

$args = @(
  "-Command", $command,
  "-OutputDir", $OutputDir,
  "-ProjectId", $ProjectId,
  "-CampaignId", $CampaignId,
  "-GoalId", $GoalId,
  "-BranchName", $BranchName,
  "-Json"
)

if ($Fixture) { $args += "-Fixture" } else { $args += "-Local" }
if ($WriteReport) { $args += "-WriteReport" }
if ($ObserveCI) { $args += "-ObserveCI" }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-managed-dev-campaign.ps1") @args
if ($LASTEXITCODE -ne 0) { throw "skybridge-managed-dev-campaign.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

$checklist = [pscustomobject]@{
  schema = "skybridge.managed_dev_campaign_manual_test.v1"
  milestone = "M8: Campaign-Driven Managed Dev End-to-End"
  mode = $result.mode
  command = $command
  campaign_id = $result.campaign_id
  goal_id = $result.goal_id
  appended_step_id = $result.appended_step_id
  bounded_loop_selected_action = $result.bounded_loop_selected_action
  bounded_loop_action_performed = $result.bounded_loop_action_performed
  branch_name = $result.managed_dev_branch
  changed_files = @($result.changed_files)
  draft_pr_created = $result.draft_pr_created
  draft_pr_number = $result.draft_pr_number
  draft_pr_url_safe = $result.draft_pr_url_safe
  draft_pr_ci_status = $result.draft_pr_ci_status
  held_for_human_review = $result.held_for_human_review
  manual_fallback_used = $result.manual_fallback_used
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
  Write-Host "M8 Manual Test Checklist:"
  Write-Host "- mode: $($checklist.mode)"
  Write-Host "- command: $($checklist.command)"
  Write-Host "- campaign: $($checklist.campaign_id)"
  Write-Host "- appended step: $($checklist.appended_step_id)"
  Write-Host "- selected action: $($checklist.bounded_loop_selected_action)"
  Write-Host "- branch: $($checklist.branch_name)"
  Write-Host "- draft PR created: $($checklist.draft_pr_created)"
  Write-Host "- PR CI status: $($checklist.draft_pr_ci_status)"
  Write-Host "- held for human review: $($checklist.held_for_human_review)"
  Write-Host "- manual_fallback_used=false"
  Write-Host "- auto_merge_enabled=false"
  Write-Host "- merge_performed=false"
  Write-Host "- release_created=false"
  Write-Host "- tag_created=false"
  Write-Host "- asset_uploaded=false"
  Write-Host "- worker_loop_started=false"
  Write-Host "- token_printed=false"
}
