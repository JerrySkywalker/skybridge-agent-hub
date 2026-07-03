. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiRuntimeRefactorSimulation `
  -Name "operator-tui-runtime-command-status" `
  -Scenario "command-status" `
  -Reset

$statuses = @($result.history | ForEach-Object { [string]$_.status })
foreach ($status in @("queued", "running", "completed")) {
  if ($statuses -notcontains $status) { throw "Missing runtime command status: $status" }
}
Assert-True $result.report.command_request_model_available "command_request_model_available"
Assert-True $result.report.command_result_model_available "command_result_model_available"

Complete-Smoke "operator-tui-runtime-command-status"
