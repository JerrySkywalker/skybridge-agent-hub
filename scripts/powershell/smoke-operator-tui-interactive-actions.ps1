. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInteractiveSimulation `
  -Name "operator-tui-interactive-actions" `
  -Scenario "actions" `
  -Reset

Assert-True $result.report.interactive_loop_available "interactive_loop_available"
Assert-True $result.report.keyboard_actions_registered "keyboard_actions_registered"
Assert-True $result.report.confirmation_input_available "confirmation_input_available"
Assert-True $result.report.reason_input_available "reason_input_available"
Assert-True $result.report.manual_gate_written "manual_gate_written"

Complete-Smoke "operator-tui-interactive-actions"
