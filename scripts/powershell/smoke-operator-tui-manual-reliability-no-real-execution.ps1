. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiManualReliabilitySmoke `
  -Name "operator-tui-manual-reliability-no-real-execution" `
  -Scenario "no-real-execution" `
  -Reset

Assert-OperatorTuiManualReliabilityNoRealExecution -Report $result.report
Assert-False $result.report.real_branch_creation_enabled "real_branch_creation_enabled"
Assert-False $result.report.real_pr_creation_enabled "real_pr_creation_enabled"
Assert-False $result.report.queue_runner_started "queue_runner_started"
Assert-False $result.report.worker_loop_started "worker_loop_started"
Assert-False $result.report.run_forever_started "run_forever_started"
Assert-False $result.report.hermes_live_called "hermes_live_called"
Assert-False $result.report.mcp_run_called "mcp_run_called"
Assert-False $result.report.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.report.release_created "release_created"
Assert-False $result.report.tag_created "tag_created"
Assert-False $result.report.asset_uploaded "asset_uploaded"
Assert-False $result.report.token_printed "token_printed"

Complete-Smoke "operator-tui-manual-reliability-no-real-execution"
