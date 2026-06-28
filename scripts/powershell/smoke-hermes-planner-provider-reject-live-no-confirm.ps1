. "$PSScriptRoot\smoke-productization-common.ps1"

$statusResult = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "live-status"
)
if (-not (@($statusResult.blockers) -contains "live_status_confirmation_required")) {
  throw "Expected live status confirmation blocker."
}
Assert-False $statusResult.live_call_attempted "live_call_attempted"
Assert-False $statusResult.live_call_succeeded "live_call_succeeded"
Assert-TokenPrintedFalse $statusResult

$planResult = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "live-plan"
)
if (-not (@($planResult.blockers) -contains "live_plan_confirmation_required")) {
  throw "Expected live plan confirmation blocker."
}
Assert-False $planResult.live_call_attempted "live_call_attempted"
Assert-False $planResult.candidate_goal_generated "candidate_goal_generated"
Assert-False $planResult.candidate_approved "candidate_approved"
Assert-False $planResult.candidate_appended "candidate_appended"
Assert-False $planResult.task_created "task_created"
Assert-False $planResult.execution_started "execution_started"
Assert-TokenPrintedFalse $planResult

Complete-Smoke "hermes-planner-provider-reject-live-no-confirm"
