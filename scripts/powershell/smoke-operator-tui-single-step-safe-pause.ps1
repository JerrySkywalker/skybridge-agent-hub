. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Initialize-OperatorTuiSingleStepCandidate

$result = Invoke-OperatorTuiSingleStepFlow `
  -Name "single-step-safe-pause" `
  -Actions @("preview", "safe-pause") `
  -Reset `
  -PauseConfirm $OperatorTuiPauseConfirmation `
  -PauseReason "fixture safe pause smoke"

Assert-True $result.report.preview_bounded_action_performed "preview_bounded_action_performed"
Assert-True $result.report.safe_pause_attempted "safe_pause_attempted"
Assert-True $result.report.safe_pause_performed "safe_pause_performed"
if ($result.report.safe_pause_result -ne "fixture_pause_metadata_recorded") {
  throw "Unexpected safe_pause_result: $($result.report.safe_pause_result)"
}
if ([string]::IsNullOrWhiteSpace([string]$result.state.safe_pause_reason)) {
  throw "safe_pause_reason missing."
}

Complete-Smoke "operator-tui-single-step-safe-pause"
