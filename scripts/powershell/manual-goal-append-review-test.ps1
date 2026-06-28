[CmdletBinding()]
param(
  [switch]$ReviewPreview,
  [switch]$Approve,
  [switch]$Reject,
  [switch]$AppendPreview,
  [switch]$AppendApply,
  [switch]$Fixture,
  [switch]$Live,
  [switch]$Json,
  [switch]$WriteReport,
  [string]$CandidatePath = "",
  [string]$ExpectedHash = "",
  [string]$CampaignId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [int]$GoalBudgetRemaining = 1,
  [string]$ApprovalReason = "",
  [string]$RejectReason = "",
  [string]$AppendReason = "",
  [string]$Confirm = "",
  [string]$OutputDir = ".agent/tmp/goal-append"
)

$ErrorActionPreference = "Stop"

if (-not $ReviewPreview -and -not $Approve -and -not $Reject -and -not $AppendPreview -and -not $AppendApply) {
  $ReviewPreview = $true
}
if (-not $Live -and -not $Fixture -and [string]::IsNullOrWhiteSpace($CandidatePath)) {
  $Fixture = $true
}
if ($Live) {
  $Fixture = $false
}

$command = if ($AppendApply) {
  "append-apply"
} elseif ($AppendPreview) {
  "append-preview"
} elseif ($Approve) {
  "approve"
} elseif ($Reject) {
  "reject"
} else {
  "review-preview"
}

$args = @(
  "-Command", $command,
  "-OutputDir", $OutputDir,
  "-ProjectId", $ProjectId,
  "-GoalBudgetRemaining", ([string]$GoalBudgetRemaining),
  "-Json"
)
if ($Fixture) { $args += "-Fixture" }
if ($Live) { $args += "-Live" }
if ($WriteReport) { $args += "-WriteReport" }
if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) { $args += @("-CandidatePath", $CandidatePath) }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHash)) { $args += @("-ExpectedHash", $ExpectedHash) }
if (-not [string]::IsNullOrWhiteSpace($CampaignId)) { $args += @("-CampaignId", $CampaignId) }
if (-not [string]::IsNullOrWhiteSpace($ApprovalReason)) { $args += @("-ApprovalReason", $ApprovalReason) }
if (-not [string]::IsNullOrWhiteSpace($RejectReason)) { $args += @("-RejectReason", $RejectReason) }
if (-not [string]::IsNullOrWhiteSpace($AppendReason)) { $args += @("-AppendReason", $AppendReason) }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-goal-append.ps1") @args
if ($LASTEXITCODE -ne 0) { throw "skybridge-goal-append.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

$checklist = [pscustomobject]@{
  schema = "skybridge.goal_append_manual_test.v1"
  milestone = "M5: Goal Append Review/Import Manual Test"
  mode = $result.mode
  action = $command
  candidate_path_safe = $result.candidate_path_safe
  candidate_hash = $result.candidate_hash
  expected_hash = $result.expected_hash
  hash_matches = $result.hash_matches
  generated_goal_id = $result.generated_goal_id
  generated_goal_title = $result.generated_goal_title
  metadata_valid = $result.metadata_valid
  safety_valid = $result.safety_valid
  human_review_required = $result.human_review_required
  import_allowed = $result.import_allowed
  execution_allowed = $result.execution_allowed
  review_state = $result.review_state
  approved = $result.approved
  rejected = $result.rejected
  append_preview_valid = $result.append_preview_valid
  append_applied = $result.append_applied
  appended_step_id = $result.appended_step_id
  appended_step_state = $result.appended_step_state
  goal_budget_remaining_before = $result.goal_budget_remaining_before
  goal_budget_remaining_after = $result.goal_budget_remaining_after
  import_performed = $result.import_performed
  approval_performed = $result.approval_performed
  append_performed = $result.append_performed
  task_created = $result.task_created
  task_claimed = $result.task_claimed
  execution_started = $result.execution_started
  codex_run_called = $result.codex_run_called
  matlab_run_called = $result.matlab_run_called
  hermes_run_called = $result.hermes_run_called
  mcp_run_called = $result.mcp_run_called
  worker_loop_started = $result.worker_loop_started
  project_control_unpaused = $result.project_control_unpaused
  blockers = @($result.blockers)
  warnings = @($result.warnings)
  token_printed = $false
  result = $result
}

if ($Json) {
  $checklist | ConvertTo-Json -Depth 90
} else {
  Write-Host "M5 Manual Test Checklist:"
  Write-Host "- candidate path: $($checklist.candidate_path_safe)"
  Write-Host "- metadata valid: $($checklist.metadata_valid)"
  Write-Host "- safety valid: $($checklist.safety_valid)"
  Write-Host "- review state: $($checklist.review_state)"
  Write-Host "- append applied: $($checklist.append_applied)"
  Write-Host "- appended step state: $($checklist.appended_step_state)"
  Write-Host "- task_created/task_claimed/execution_started: false"
  Write-Host "- worker_loop_started=false"
  Write-Host "- token_printed=false"
}
