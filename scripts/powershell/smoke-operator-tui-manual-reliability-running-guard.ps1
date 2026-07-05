. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiManualReliabilitySmoke `
  -Name "operator-tui-manual-reliability-running-guard" `
  -Scenario "running-guard" `
  -Reset

Assert-True $result.running_guard.running_guard_visible "running_guard_visible"
Assert-True $result.running_guard.mutation_actions_blocked_while_running "mutation_actions_blocked_while_running"
Assert-True $result.running_guard.command_already_running_feedback_visible "command_already_running_feedback_visible"
Assert-True $result.running_guard.elapsed_seconds_visible "elapsed_seconds_visible"
Assert-True $result.running_guard.expected_wait_behavior_visible "expected_wait_behavior_visible"
Assert-False $result.running_guard.token_printed "token_printed"

Complete-Smoke "operator-tui-manual-reliability-running-guard"
