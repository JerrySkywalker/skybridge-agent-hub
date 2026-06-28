. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "status", "-Fixture")
if ([string]$result.schema -ne "skybridge.local_goal_generator.v1") { throw "Unexpected schema." }
if ([string]$result.mode -ne "fixture") { throw "Expected fixture mode." }
Assert-True $result.provider_inventory_checked "provider_inventory_checked"
Assert-True $result.direct_provider_available "direct_provider_available"
Assert-False $result.codex_generation_called "codex_generation_called"
Assert-False $result.proposed_goal_written "proposed_goal_written"
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "local-goal-generator-status"
