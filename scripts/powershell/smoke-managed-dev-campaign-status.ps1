. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "status",
  "-Fixture"
)

if ($result.schema -ne "skybridge.managed_dev_campaign.v1") { throw "Unexpected managed-dev campaign schema." }
if ($result.mode -ne "fixture") { throw "Expected fixture mode." }
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-status"
