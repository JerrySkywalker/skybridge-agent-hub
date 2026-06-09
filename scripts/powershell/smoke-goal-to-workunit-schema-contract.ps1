. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$schema = Invoke-GoalToWorkunitJson "schema"
foreach ($required in @("skybridge.proposed_goal_workunit_candidate.v1", "skybridge.goal_to_workunit_conversion.v1", "skybridge.workunit_candidate_pack.v1", "skybridge.workunit_candidate_review.v1", "skybridge.workunit_candidate_risk_gate.v1", "skybridge.workunit_candidate_manifest.v1")) {
  if (@($schema.schemas) -notcontains $required) { throw "Missing schema $required" }
}
Write-SmokeResult "goal-to-workunit-schema-contract"
