. "$PSScriptRoot\operator-tui-smoke-common.ps1"

Initialize-OperatorTuiSingleStepCandidate

$result = Invoke-OperatorTuiSingleStepFlow `
  -Name "single-step-no-loop" `
  -Actions @("preview", "start-fixture", "safe-pause", "abort-preview") `
  -Reset `
  -StartConfirm $OperatorTuiStartConfirmation `
  -PauseConfirm $OperatorTuiPauseConfirmation `
  -PauseReason "fixture no loop smoke" `
  -AbortReason "fixture no loop abort preview"

Assert-True $result.report.start_one_goal_attempted "start_one_goal_attempted"
Assert-True $result.report.start_one_goal_performed "start_one_goal_performed"
Assert-False $result.report.worker_loop_started "worker_loop_started"
Assert-False $result.report.queue_runner_started "queue_runner_started"
Assert-False $result.report.run_forever_started "run_forever_started"
Assert-False $result.report.task_created "task_created"
Assert-False $result.report.task_claimed "task_claimed"
Assert-False $result.report.execution_started "execution_started"

Complete-Smoke "operator-tui-single-step-no-loop"
