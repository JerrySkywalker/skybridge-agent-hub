. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInteractiveSimulation `
  -Name "operator-tui-interactive-no-real-execution" `
  -Scenario "no-real-execution" `
  -Reset

Assert-OperatorTuiInteractiveNoRealExecution -Report $result.report

$candidateReportPath = Join-Path $RepoRoot "$($result.output_dir)/operator-tui-candidate-report.json"
$singleStepReportPath = Join-Path $RepoRoot "$($result.output_dir)/operator-tui-single-step-report.json"
$candidateReport = Get-Content -Raw -LiteralPath $candidateReportPath | ConvertFrom-Json
$singleStepReport = Get-Content -Raw -LiteralPath $singleStepReportPath | ConvertFrom-Json
Assert-False $candidateReport.task_created "candidate task_created"
Assert-False $candidateReport.task_claimed "candidate task_claimed"
Assert-False $candidateReport.execution_started "candidate execution_started"
Assert-False $candidateReport.branch_created "candidate branch_created"
Assert-False $candidateReport.pr_created "candidate pr_created"
Assert-False $candidateReport.worker_loop_started "candidate worker_loop_started"
Assert-False $candidateReport.queue_runner_started "candidate queue_runner_started"
Assert-False $candidateReport.hermes_live_called "candidate hermes_live_called"
Assert-False $candidateReport.mcp_run_called "candidate mcp_run_called"
Assert-False $singleStepReport.task_created "single_step task_created"
Assert-False $singleStepReport.task_claimed "single_step task_claimed"
Assert-False $singleStepReport.execution_started "single_step execution_started"
Assert-False $singleStepReport.branch_created "single_step branch_created"
Assert-False $singleStepReport.pr_created "single_step pr_created"
Assert-False $singleStepReport.worker_loop_started "single_step worker_loop_started"
Assert-False $singleStepReport.queue_runner_started "single_step queue_runner_started"
Assert-False $singleStepReport.run_forever_started "single_step run_forever_started"
Assert-False $singleStepReport.hermes_live_called "single_step hermes_live_called"
Assert-False $singleStepReport.mcp_run_called "single_step mcp_run_called"
Assert-False $singleStepReport.auto_merge_enabled "single_step auto_merge_enabled"
Assert-False $singleStepReport.release_created "single_step release_created"
Assert-False $singleStepReport.tag_created "single_step tag_created"
Assert-False $singleStepReport.asset_uploaded "single_step asset_uploaded"
Assert-TokenPrintedFalse $candidateReport
Assert-TokenPrintedFalse $singleStepReport

Complete-Smoke "operator-tui-interactive-no-real-execution"
