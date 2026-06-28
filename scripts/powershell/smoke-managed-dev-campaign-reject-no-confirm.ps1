. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "bounded-apply-one",
  "-Fixture"
)

if (-not (@($result.blockers) -contains "missing_campaign_managed_dev_action_confirmation")) {
  throw "Expected missing confirmation blocker."
}
Assert-False $result.bounded_loop_action_performed "bounded_loop_action_performed"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-reject-no-confirm"
