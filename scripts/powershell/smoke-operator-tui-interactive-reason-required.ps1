. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInteractiveSimulation `
  -Name "operator-tui-interactive-reason-required" `
  -Scenario "reason-required" `
  -Reset

Assert-True $result.report.reason_required_enforced "reason_required_enforced"
if ($result.last_action.status -ne "blocked") { throw "Expected blocked last action." }
if ($result.last_action.result -ne "reason_required") { throw "Expected reason required result." }
Assert-False $result.report.real_task_execution_enabled "real_task_execution_enabled"

Complete-Smoke "operator-tui-interactive-reason-required"
