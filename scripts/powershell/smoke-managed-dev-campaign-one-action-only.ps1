. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "run-fixture-e2e",
  "-Fixture",
  "-Confirm", $confirm
)

if ($result.bounded_loop_selected_action -ne "managed_dev_draft_pr") { throw "Expected one managed-dev action." }
Assert-True $result.bounded_loop_action_performed "bounded_loop_action_performed"
if (@($result.changed_files).Count -ne 1) { throw "Expected exactly one changed file for one action." }
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-one-action-only"
