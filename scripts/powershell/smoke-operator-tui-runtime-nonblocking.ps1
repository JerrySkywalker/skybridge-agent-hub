. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiRuntimeRefactorSimulation `
  -Name "operator-tui-runtime-nonblocking" `
  -Scenario "nonblocking" `
  -Reset

Assert-True $result.report.ui_loop_nonblocking "ui_loop_nonblocking"
Assert-True $result.report.background_command_runner_available "background_command_runner_available"
Assert-True $result.report.running_state_rendered "running_state_rendered"
if ($result.report.last_command_status -ne "completed") { throw "Expected completed runtime command." }

Complete-Smoke "operator-tui-runtime-nonblocking"
