. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiRuntimeRefactorSimulation `
  -Name "operator-tui-runtime-timeout" `
  -Scenario "timeout" `
  -Reset

Assert-True $result.report.command_timeout_enforced "command_timeout_enforced"
Assert-True $result.timeout.timed_out "timeout.timed_out"
if ($result.report.last_command_status -ne "timed_out") { throw "Expected timed_out last command status." }
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-runtime-timeout"
