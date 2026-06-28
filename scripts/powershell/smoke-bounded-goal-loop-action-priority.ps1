. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "preview",
  "-Fixture",
  "-Scenario", "priority"
)
Assert-True $result.ready_step_detected "ready_step_detected"
Assert-True $result.reviewed_candidate_detected "reviewed_candidate_detected"
if ([string]$result.selected_action -ne "execute_ready_step") { throw "Ready step priority not enforced." }
Assert-False $result.action_performed "action_performed"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-action-priority"
