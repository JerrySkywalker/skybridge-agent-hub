. "$PSScriptRoot\smoke-productization-common.ps1"

$boundedConfirm = "I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY"
$appendConfirm = "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"
$scenarios = @(
  @{ name = "ready-step"; confirm = $boundedConfirm; expected = "execute_ready_step" },
  @{ name = "reviewed-candidate"; confirm = "$boundedConfirm;$appendConfirm"; expected = "append_reviewed_goal" },
  @{ name = "generate"; confirm = $boundedConfirm; expected = "generate_proposed_goal" },
  @{ name = "budget-exhausted"; confirm = $boundedConfirm; expected = "hold"; budget = "0" }
)

foreach ($scenario in $scenarios) {
  $args = @(
    "-Fixture",
    "-Scenario", $scenario.name,
    "-ApplyOne",
    "-Confirm", $scenario.confirm
  )
  if ($scenario.ContainsKey("budget")) {
    $args += @("-GoalBudgetRemaining", $scenario.budget)
  }
  $result = Invoke-JsonScript "manual-bounded-goal-loop-test.ps1" $args
  if ([string]$result.schema -ne "skybridge.bounded_goal_loop_manual_test.v1") { throw "Unexpected manual schema." }
  if ([string]$result.selected_action -ne $scenario.expected) { throw "Unexpected manual selected action for $($scenario.name)." }
  Assert-False $result.worker_loop_started "worker_loop_started"
  Assert-TokenPrintedFalse $result
}

Complete-Smoke "manual-bounded-goal-loop-fixture"
