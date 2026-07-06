$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b1RealProviderImplementation -Scenario "no-real-execution" -Reset

Assert-OperatorTuiMg371b1NoRealExecution `
  -Report $result.report `
  -Safety $result.safety
Assert-False $result.report.worker_loop_started "worker_loop_started"
Assert-False $result.report.queue_runner_started "queue_runner_started"
Assert-False $result.report.run_forever_started "run_forever_started"
Assert-False $result.report.hermes_live_called "hermes_live_called"
Assert-False $result.report.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b1-no-real-execution"
