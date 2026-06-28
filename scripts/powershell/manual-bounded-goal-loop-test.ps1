[CmdletBinding()]
param(
  [switch]$Preview,
  [switch]$ApplyOne,
  [switch]$Fixture,
  [switch]$Live,
  [ValidateSet("ready-step", "reviewed-candidate", "generate", "budget-exhausted", "priority")]
  [string]$Scenario = "ready-step",
  [switch]$Json,
  [switch]$WriteReport,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignId = "",
  [string]$WorkerId = "",
  [int]$GoalBudgetRemaining = 1,
  [int]$GoalBudgetLimit = 1,
  [string]$Objective = "Bounded loop manual fixture objective.",
  [string]$CandidatePath = "",
  [string]$ExpectedHash = "",
  [int]$MaxActionsPerRun = 1,
  [int]$MaxStepsPerRun = 1,
  [int]$MaxGeneratedGoalsPerRun = 1,
  [switch]$UseCodex,
  [switch]$NoCodex,
  [string]$Confirm = "",
  [string]$OutputDir = ".agent/tmp/bounded-goal-loop"
)

$ErrorActionPreference = "Stop"

if (-not $Preview -and -not $ApplyOne) { $Preview = $true }
if (-not $Live -and -not $Fixture) { $Fixture = $true }
if ($Live) { $Fixture = $false }

$command = if ($ApplyOne) { "apply-one" } else { "preview" }
$args = @(
  "-Command", $command,
  "-Scenario", $Scenario,
  "-OutputDir", $OutputDir,
  "-ProjectId", $ProjectId,
  "-GoalBudgetRemaining", ([string]$GoalBudgetRemaining),
  "-GoalBudgetLimit", ([string]$GoalBudgetLimit),
  "-Objective", $Objective,
  "-MaxActionsPerRun", ([string]$MaxActionsPerRun),
  "-MaxStepsPerRun", ([string]$MaxStepsPerRun),
  "-MaxGeneratedGoalsPerRun", ([string]$MaxGeneratedGoalsPerRun),
  "-Json"
)
if ($Fixture) { $args += "-Fixture" }
if ($Live) { $args += "-Live" }
if ($WriteReport) { $args += "-WriteReport" }
if ($UseCodex) { $args += "-UseCodex" }
if ($NoCodex) { $args += "-NoCodex" }
if (-not [string]::IsNullOrWhiteSpace($CampaignId)) { $args += @("-CampaignId", $CampaignId) }
if (-not [string]::IsNullOrWhiteSpace($WorkerId)) { $args += @("-WorkerId", $WorkerId) }
if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) { $args += @("-CandidatePath", $CandidatePath) }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHash)) { $args += @("-ExpectedHash", $ExpectedHash) }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-bounded-goal-loop.ps1") @args
if ($LASTEXITCODE -ne 0) { throw "skybridge-bounded-goal-loop.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

$checklist = [pscustomobject]@{
  schema = "skybridge.bounded_goal_loop_manual_test.v1"
  milestone = "M6: Bounded Goal Budget Loop Manual Test"
  mode = $result.mode
  scenario = $Scenario
  action = $command
  selected_action = $result.selected_action
  selected_action_reason = $result.selected_action_reason
  action_count = $result.action_count
  selected_step_id = $result.selected_step_id
  selected_task_id = $result.selected_task_id
  generated_goal_id = $result.generated_goal_id
  generated_goal_path_safe = $result.generated_goal_path_safe
  selected_candidate_hash = $result.selected_candidate_hash
  appended_step_id = $result.appended_step_id
  appended_step_state = $result.appended_step_state
  goal_budget_remaining_before = $result.goal_budget_remaining_before
  goal_budget_remaining_after = $result.goal_budget_remaining_after
  task_created = $result.task_created
  task_claimed = $result.task_claimed
  execution_started = $result.execution_started
  execution_completed = $result.execution_completed
  goal_generated = $result.goal_generated
  goal_reviewed = $result.goal_reviewed
  goal_appended = $result.goal_appended
  appended_step_executed = $result.appended_step_executed
  worker_loop_started = $result.worker_loop_started
  hermes_run_called = $result.hermes_run_called
  mcp_run_called = $result.mcp_run_called
  project_control_unpaused = $result.project_control_unpaused
  blockers = @($result.blockers)
  warnings = @($result.warnings)
  token_printed = $false
  result = $result
}

if ($Json) {
  $checklist | ConvertTo-Json -Depth 90
} else {
  Write-Host "M6 Manual Test Checklist:"
  Write-Host "- scenario: $($checklist.scenario)"
  Write-Host "- selected action: $($checklist.selected_action)"
  Write-Host "- action count: $($checklist.action_count)"
  Write-Host "- budget before/after: $($checklist.goal_budget_remaining_before)/$($checklist.goal_budget_remaining_after)"
  Write-Host "- task_created/task_claimed/execution_started: $($checklist.task_created)/$($checklist.task_claimed)/$($checklist.execution_started)"
  Write-Host "- generated/appended: $($checklist.goal_generated)/$($checklist.goal_appended)"
  Write-Host "- appended_step_executed=false"
  Write-Host "- worker_loop_started=false"
  Write-Host "- token_printed=false"
}
