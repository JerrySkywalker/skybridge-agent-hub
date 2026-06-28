. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "run-fixture-e2e",
  "-Fixture",
  "-Confirm", $confirm
)

Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.production_infra_mutated "production_infra_mutated"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-no-auto-merge"
