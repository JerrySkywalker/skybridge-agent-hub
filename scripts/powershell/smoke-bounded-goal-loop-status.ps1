. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "status",
  "-Fixture",
  "-Scenario", "ready-step"
)
if ([string]$result.schema -ne "skybridge.bounded_goal_loop.v1") { throw "Unexpected schema." }
if ([string]$result.mode -ne "fixture") { throw "Unexpected mode." }
Assert-True $result.preview_only "preview_only"
Assert-True $result.provider_inventory_checked "provider_inventory_checked"
Assert-True $result.direct_provider_available "direct_provider_available"
Assert-False $result.action_performed "action_performed"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-status"
