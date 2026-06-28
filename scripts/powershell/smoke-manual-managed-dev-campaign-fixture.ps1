. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-managed-dev-campaign-test.ps1") `
  -Fixture `
  -RunFixture `
  -Confirm $confirm `
  -Json
if ($LASTEXITCODE -ne 0) { throw "manual-managed-dev-campaign-test.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

if ($result.schema -ne "skybridge.managed_dev_campaign_manual_test.v1") { throw "Unexpected manual MG362 schema." }
if ($result.milestone -ne "M8: Campaign-Driven Managed Dev End-to-End") { throw "Unexpected milestone." }
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-managed-dev-campaign-fixture"
