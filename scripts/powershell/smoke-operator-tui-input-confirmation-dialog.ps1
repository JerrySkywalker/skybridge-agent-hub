. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInputUxSmoke `
  -Name "operator-tui-input-confirmation-dialog" `
  -Scenario "confirmation-dialog" `
  -Reset

Assert-True $result.report.confirmation_dialog_available "confirmation_dialog_available"
Assert-True $result.report.required_confirmation_visible "required_confirmation_visible"
Assert-True $result.report.input_match_indicator_available "input_match_indicator_available"
if ($result.confirmation_snapshot -notmatch [regex]::Escape($OperatorTuiReviewConfirmation)) {
  throw "Confirmation dialog snapshot missing exact review confirmation."
}
if ($result.state.current_input_length -le 0) { throw "Confirmation dialog smoke did not accept pasted input characters." }

Complete-Smoke "operator-tui-input-confirmation-dialog"
