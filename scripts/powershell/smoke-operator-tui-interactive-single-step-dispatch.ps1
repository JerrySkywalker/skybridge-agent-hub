. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInteractiveSimulation `
  -Name "operator-tui-interactive-single-step-dispatch" `
  -Scenario "single-step-dispatch" `
  -Reset

Assert-True $result.report.candidate_actions_dispatchable "candidate_actions_dispatchable"
Assert-True $result.report.single_step_actions_dispatchable "single_step_actions_dispatchable"

$singleStepReportPath = Join-Path $RepoRoot "$($result.output_dir)/operator-tui-single-step-report.json"
if (-not (Test-Path -LiteralPath $singleStepReportPath -PathType Leaf)) { throw "Missing single-step dispatch report." }
$singleStepReport = Get-Content -Raw -LiteralPath $singleStepReportPath | ConvertFrom-Json
Assert-True $singleStepReport.preview_bounded_action_performed "preview_bounded_action_performed"
Assert-True $singleStepReport.start_one_goal_attempted "start_one_goal_attempted"
Assert-True $singleStepReport.start_one_goal_performed "start_one_goal_performed"
Assert-True $singleStepReport.safe_pause_attempted "safe_pause_attempted"
Assert-True $singleStepReport.safe_pause_performed "safe_pause_performed"
Assert-True $singleStepReport.abort_terminate_attempted "abort_terminate_attempted"
Assert-False $singleStepReport.abort_terminate_performed "abort_terminate_performed"
Assert-False $singleStepReport.execution_started "single_step execution_started"
Assert-False $singleStepReport.branch_created "single_step branch_created"
Assert-False $singleStepReport.pr_created "single_step pr_created"
Assert-TokenPrintedFalse $singleStepReport

Complete-Smoke "operator-tui-interactive-single-step-dispatch"
