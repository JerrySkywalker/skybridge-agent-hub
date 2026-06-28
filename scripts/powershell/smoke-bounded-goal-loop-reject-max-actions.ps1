. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "ready-step",
  "-MaxActionsPerRun", "2",
  "-MaxStepsPerRun", "2",
  "-MaxGeneratedGoalsPerRun", "2",
  "-Confirm", $confirm
)
$blockers = @($result.blockers)
foreach ($expected in @("max_actions_per_run_must_be_1", "max_steps_per_run_must_be_1", "max_generated_goals_per_run_must_be_1")) {
  if (-not ($blockers -contains $expected)) { throw "Missing blocker: $expected" }
}
Assert-False $result.action_performed "action_performed"
if ([int]$result.action_count -ne 0) { throw "Rejected max run performed action." }
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-reject-max-actions"
