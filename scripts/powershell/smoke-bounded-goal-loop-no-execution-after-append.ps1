. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY;I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "reviewed-candidate",
  "-Confirm", $confirm
)
if ([string]$result.selected_action -ne "append_reviewed_goal") { throw "Unexpected selected action." }
Assert-True $result.goal_appended "goal_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.execution_completed "execution_completed"
Assert-False $result.step_completed "step_completed"
Assert-False $result.appended_step_executed "appended_step_executed"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-no-execution-after-append"
