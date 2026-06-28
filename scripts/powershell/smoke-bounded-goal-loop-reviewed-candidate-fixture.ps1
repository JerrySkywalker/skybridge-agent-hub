. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY;I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "reviewed-candidate",
  "-Confirm", $confirm
)
if ([string]$result.selected_action -ne "append_reviewed_goal") { throw "Unexpected selected action." }
Assert-True $result.action_performed "action_performed"
if ([int]$result.action_count -ne 1) { throw "Expected exactly one action." }
Assert-True $result.goal_reviewed "goal_reviewed"
Assert-True $result.goal_appended "goal_appended"
if ([string]$result.appended_step_id -ne "bounded-loop-appended-generated-goal-356-001") { throw "Unexpected appended step id." }
if ([string]$result.appended_step_state -ne "pending") { throw "Unexpected appended step state." }
if ([int]$result.goal_budget_remaining_before -ne 1 -or [int]$result.goal_budget_remaining_after -ne 0) { throw "Append did not consume one budget unit." }
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.appended_step_executed "appended_step_executed"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-reviewed-candidate-fixture"
