. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "preview-once", "-Fixture")
if ($result.schema -ne "skybridge.single_goal_loop.v1") { throw "Unexpected schema." }
Assert-True $result.preview_only "preview_only"
Assert-True $result.provider_inventory_checked "provider_inventory_checked"
Assert-True $result.direct_provider_available "direct_provider_available"
if (@($result.blockers).Count -ne 0) { throw "Fixture preview should not be blocked." }
Assert-False $result.apply_confirmed "apply_confirmed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.evidence_attached "evidence_attached"
Assert-TokenPrintedFalse $result

Complete-Smoke "single-goal-loop-preview"
