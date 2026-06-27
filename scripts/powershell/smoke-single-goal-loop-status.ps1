. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "status", "-Fixture")
if ($result.schema -ne "skybridge.single_goal_loop.v1") { throw "Unexpected schema." }
if ($result.mode -ne "fixture") { throw "Expected fixture mode." }
Assert-True $result.provider_inventory_checked "provider_inventory_checked"
Assert-True $result.direct_provider_available "direct_provider_available"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "single-goal-loop-status"
