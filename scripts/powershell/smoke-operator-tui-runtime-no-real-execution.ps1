. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiRuntimeRefactorSimulation `
  -Name "operator-tui-runtime-no-real-execution" `
  -Scenario "no-real-execution" `
  -Reset

Assert-OperatorTuiRuntimeNoRealExecution -Report $result.report
Assert-False $result.state.safety_flags.task_created "state task_created"
Assert-False $result.state.safety_flags.task_claimed "state task_claimed"
Assert-False $result.state.safety_flags.execution_started "state execution_started"
Assert-False $result.state.safety_flags.worker_loop_started "state worker_loop_started"
Assert-False $result.state.safety_flags.queue_runner_started "state queue_runner_started"
Assert-False $result.state.safety_flags.run_forever_started "state run_forever_started"
Assert-False $result.state.safety_flags.hermes_live_called "state hermes_live_called"
Assert-False $result.state.safety_flags.mcp_run_called "state mcp_run_called"
Assert-False $result.state.safety_flags.auto_merge_enabled "state auto_merge_enabled"
Assert-False $result.state.safety_flags.release_created "state release_created"
Assert-False $result.state.safety_flags.tag_created "state tag_created"
Assert-False $result.state.safety_flags.asset_uploaded "state asset_uploaded"
Assert-False $result.state.safety_flags.token_printed "state token_printed"

Complete-Smoke "operator-tui-runtime-no-real-execution"
