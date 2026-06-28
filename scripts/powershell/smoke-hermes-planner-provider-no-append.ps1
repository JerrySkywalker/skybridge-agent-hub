. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "fixture-plan",
  "-OutputDir", ".agent/tmp/hermes-planner-provider/smoke-no-append-$([guid]::NewGuid().ToString('N'))"
)

Assert-True $result.candidate_goal_generated "candidate_goal_generated"
Assert-True $result.candidate_validated "candidate_validated"
Assert-False $result.candidate_approved "candidate_approved"
Assert-False $result.candidate_appended "candidate_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.branch_created "branch_created"
Assert-False $result.pr_created "pr_created"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.deploy_triggered "deploy_triggered"
Assert-TokenPrintedFalse $result

Complete-Smoke "hermes-planner-provider-no-append"
