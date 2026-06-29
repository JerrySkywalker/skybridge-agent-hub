. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiCandidateFlow `
  -Name "operator-tui-candidate-no-execution" `
  -Actions @("generate", "validate", "review-approve", "append-preview", "append-apply-fixture") `
  -Reset `
  -ReviewConfirm $OperatorTuiReviewConfirmation `
  -AppendConfirm $OperatorTuiAppendConfirmation

Assert-True $result.report.append_performed "append_performed"
Assert-False $result.report.task_created "task_created"
Assert-False $result.report.task_claimed "task_claimed"
Assert-False $result.report.execution_started "execution_started"
Assert-False $result.report.branch_created "branch_created"
Assert-False $result.report.pr_created "pr_created"
Assert-False $result.report.worker_loop_started "worker_loop_started"
Assert-False $result.report.queue_runner_started "queue_runner_started"
Assert-False $result.report.hermes_live_called "hermes_live_called"
Assert-False $result.report.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-candidate-no-execution"
