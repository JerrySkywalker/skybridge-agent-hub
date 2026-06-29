. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Initialize-OperatorTuiSingleStepCandidate

$result = Invoke-OperatorTuiSingleStepFlow `
  -Name "single-step-start-fixture" `
  -Actions @("preview", "start-fixture") `
  -Reset `
  -StartConfirm $OperatorTuiStartConfirmation

Assert-True $result.report.preview_bounded_action_performed "preview_bounded_action_performed"
Assert-True $result.report.start_one_goal_attempted "start_one_goal_attempted"
Assert-True $result.report.start_one_goal_performed "start_one_goal_performed"
if ($result.state.start_one_mode -ne "fixture") { throw "start_one_mode must be fixture." }
if ($result.report.start_one_goal_result -ne "fixture_single_step_gate_exercised_no_execution") {
  throw "Unexpected start_one_goal_result: $($result.report.start_one_goal_result)"
}
Assert-False $result.report.execution_started "execution_started"

Complete-Smoke "operator-tui-single-step-start-fixture"
