. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "status",
  "-Fixture"
)
if ($result.schema -ne "skybridge.managed_dev_pilot.v1") { throw "Unexpected managed dev pilot schema." }
if ($result.mode -ne "fixture") { throw "Expected fixture mode." }
Assert-True $result.preview_only "preview_only"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-pilot-status"
