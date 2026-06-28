. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "ready-step",
  "-Confirm", $confirm
)
if ([string]$result.selected_action -ne "execute_ready_step") { throw "Unexpected selected action." }
Assert-False $result.preview_only "preview_only"
Assert-True $result.action_performed "action_performed"
if ([int]$result.action_count -ne 1) { throw "Expected exactly one action." }
Assert-True $result.task_created "task_created"
Assert-True $result.task_claimed "task_claimed"
Assert-True $result.execution_started "execution_started"
Assert-True $result.execution_completed "execution_completed"
Assert-True $result.evidence_attached "evidence_attached"
Assert-True $result.step_completed "step_completed"
if ([int]$result.task_created_count -ne 1 -or [int]$result.task_claimed_count -ne 1 -or [int]$result.execution_completed_count -ne 1) { throw "Unexpected ready-step counts." }
if ([int]$result.goal_budget_remaining_before -ne [int]$result.goal_budget_remaining_after) { throw "Ready step changed goal budget." }
Assert-False $result.goal_generated "goal_generated"
Assert-False $result.goal_appended "goal_appended"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-ready-step-fixture"
