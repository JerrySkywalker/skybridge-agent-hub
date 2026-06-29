. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Initialize-OperatorTuiSingleStepCandidate

$result = Invoke-OperatorTuiSingleStepFlow `
  -Name "single-step-abort-preview" `
  -Actions @("preview", "abort-preview") `
  -Reset `
  -AbortReason "fixture abort preview smoke"

Assert-True $result.report.preview_bounded_action_performed "preview_bounded_action_performed"
Assert-True $result.report.abort_terminate_attempted "abort_terminate_attempted"
Assert-False $result.report.abort_terminate_performed "abort_terminate_performed"
Assert-True $result.state.abort_previewed "state.abort_previewed"
if ($result.report.abort_terminate_result -ne "abort_preview_only_no_process_kill") {
  throw "Unexpected abort_terminate_result: $($result.report.abort_terminate_result)"
}

Complete-Smoke "operator-tui-single-step-abort-preview"
