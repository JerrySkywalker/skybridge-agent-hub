. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiRuntimeRefactorSimulation `
  -Name "operator-tui-runtime-stale-result" `
  -Scenario "stale-result" `
  -Reset

Assert-True $result.report.stale_result_ignored "report.stale_result_ignored"
Assert-True $result.stale.stale_result_ignored "stale.stale_result_ignored"
$staleHistory = @($result.history | Where-Object { $_.stale_result_ignored -eq $true })
if ($staleHistory.Count -lt 1) { throw "Expected at least one stale ignored history entry." }
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-runtime-stale-result"
