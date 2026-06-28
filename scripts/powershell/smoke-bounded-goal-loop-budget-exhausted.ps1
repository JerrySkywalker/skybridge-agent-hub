. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "budget-exhausted",
  "-GoalBudgetRemaining", "0",
  "-Confirm", $confirm
)
if ([string]$result.selected_action -ne "hold") { throw "Budget exhausted should hold." }
Assert-True $result.campaign_held "campaign_held"
Assert-False $result.action_performed "action_performed"
Assert-False $result.goal_generated "goal_generated"
Assert-False $result.goal_appended "goal_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
if ([int]$result.goal_budget_remaining_after -ne 0) { throw "Budget exhausted changed budget." }
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-budget-exhausted"
