. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture", "-Confirm", "I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY")
if ($result.schema -ne "skybridge.single_goal_loop.v1") { throw "Unexpected schema." }
Assert-False $result.preview_only "preview_only"
Assert-True $result.apply_confirmed "apply_confirmed"
Assert-True $result.task_created "task_created"
Assert-True $result.task_claimed "task_claimed"
Assert-True $result.execution_started "execution_started"
Assert-True $result.execution_completed "execution_completed"
Assert-False $result.execution_failed "execution_failed"
Assert-True $result.evidence_attached "evidence_attached"
Assert-True $result.step_completed "step_completed"
Assert-True $result.campaign_completed "campaign_completed"
if ([int]$result.task_created_count -ne 1) { throw "Expected one created fixture task." }
if ([int]$result.task_claimed_count -ne 1) { throw "Expected one claimed fixture task." }
if ([int]$result.execution_completed_count -ne 1) { throw "Expected one completed fixture task." }
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "single-goal-loop-fixture"
