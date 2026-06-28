. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE"
$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "create-draft-pr",
  "-Fixture",
  "-Confirm", $confirm
)

if (-not (@($result.blockers) -contains "fixture_mode_never_creates_real_pr")) {
  throw "Expected fixture no-real-PR blocker."
}
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-no-real-pr-fixture"
