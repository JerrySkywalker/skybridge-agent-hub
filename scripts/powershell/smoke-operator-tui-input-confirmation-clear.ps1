. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInputUxSmoke `
  -Name "operator-tui-input-confirmation-clear" `
  -Scenario "confirmation-clear" `
  -Reset

Assert-True $result.state.ctrl_u_clear_used "ctrl_u_clear_used"
Assert-True $result.state.backspace_used "backspace_used"
Assert-True $result.state.esc_cancel_used "esc_cancel_used"
Assert-True $result.state.paste_friendly_input_observed "paste_friendly_input_observed"
Assert-True $result.report.ctrl_u_clear_available "ctrl_u_clear_available"
Assert-True $result.report.backspace_available "backspace_available"
Assert-True $result.report.esc_cancel_available "esc_cancel_available"

Complete-Smoke "operator-tui-input-confirmation-clear"
