. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiRuntimeRefactorSimulation `
  -Name "operator-tui-runtime-one-command" `
  -Scenario "one-command" `
  -Reset

Assert-True $result.report.one_command_at_a_time_enforced "one_command_at_a_time_enforced"
$blocked = @($result.history | Where-Object {
  [string]$_.status -eq "blocked" -and [string]$_.result_summary -eq "command_already_running"
})
if ($blocked.Count -lt 1) { throw "Expected command_already_running block." }
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-runtime-one-command"
