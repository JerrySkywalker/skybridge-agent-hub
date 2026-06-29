. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Initialize-OperatorTuiSingleStepCandidate

$result = Invoke-OperatorTuiSingleStepFlow `
  -Name "single-step-preview" `
  -Actions @("preview") `
  -Reset

Assert-True $result.report.preview_bounded_action_performed "preview_bounded_action_performed"
if ($result.report.preview_bounded_action_result -ne "allowed_fixture_single_step") {
  throw "Unexpected preview result: $($result.report.preview_bounded_action_result)"
}
Assert-True $result.state.next_bounded_action_previewed "state.next_bounded_action_previewed"
Assert-True $result.state.next_bounded_action_allowed "state.next_bounded_action_allowed"
if ($result.state.next_bounded_action_type -ne "fixture_single_step_start_gate") {
  throw "Unexpected bounded action type: $($result.state.next_bounded_action_type)"
}
Assert-False $result.report.start_one_goal_attempted "start_one_goal_attempted"
Assert-False $result.report.start_one_goal_performed "start_one_goal_performed"

Complete-Smoke "operator-tui-single-step-preview"
