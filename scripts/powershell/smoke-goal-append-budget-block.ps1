. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-budget-block-$([guid]::NewGuid().ToString('N'))"
$approveConfirm = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
$appendConfirm = "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"
Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "approve",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-GoalBudgetRemaining", "1",
  "-ApprovalReason", "Operator approved fixture metadata review only.",
  "-Confirm", $approveConfirm
) | Out-Null

$result = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "append-apply",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-GoalBudgetRemaining", "0",
  "-AppendReason", "Operator appended fixture metadata only.",
  "-Confirm", $appendConfirm
)
if (-not (@($result.blockers) -contains "goal_budget_exhausted")) { throw "Missing budget blocker." }
Assert-False $result.append_applied "append_applied"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

$campaignState = Join-Path (Join-Path $RepoRoot $outputDir) "campaign-state.json"
if (Test-Path -LiteralPath $campaignState) { throw "budget-block append wrote campaign state." }

Complete-Smoke "goal-append-budget-block"
