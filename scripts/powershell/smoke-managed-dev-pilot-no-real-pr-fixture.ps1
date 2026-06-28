. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE"
$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "create-draft-pr",
  "-Fixture",
  "-Confirm", $confirm
)
if (-not (@($result.blockers) -contains "fixture_mode_never_creates_real_pr")) {
  throw "Expected fixture_mode_never_creates_real_pr blocker."
}
Assert-True $result.draft_pr_requested "draft_pr_requested"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-pilot-no-real-pr-fixture"
