. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "status", "-Fixture", "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-status")
if ($result.schema -ne "skybridge.multi_goal_loop.v1") { throw "Unexpected schema." }
Assert-True $result.preview_only "preview_only"
Assert-True $result.provider_inventory_checked "provider_inventory_checked"
Assert-True $result.direct_provider_available "direct_provider_available"
if (@($result.steps).Count -ne 3) { throw "Expected three static steps." }
if ([string]$result.next_step_id -ne "safe-local-smoke-step-353-001") { throw "Expected first ready step." }
if ([int]$result.selected_step_count -ne 1) { throw "Expected one selected step." }
if ([int]$result.selected_task_count -ne 1) { throw "Expected one selected task." }
if (@($result.blockers).Count -ne 0) { throw "Status should not be blocked." }
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "multi-goal-loop-status"
