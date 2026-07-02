. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInteractiveSimulation `
  -Name "operator-tui-interactive-confirmation-reject" `
  -Scenario "confirmation-reject" `
  -Reset

Assert-True $result.report.exact_confirmation_mismatch_rejected "exact_confirmation_mismatch_rejected"
if ($result.last_action.status -ne "blocked") { throw "Expected blocked last action." }
if ($result.last_action.result -ne "exact_confirmation_mismatch") { throw "Expected exact confirmation mismatch result." }
Assert-False $result.report.real_task_execution_enabled "real_task_execution_enabled"

Complete-Smoke "operator-tui-interactive-confirmation-reject"
