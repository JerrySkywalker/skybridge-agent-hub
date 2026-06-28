. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
$result = Invoke-JsonScript "manual-managed-dev-pr-pilot.ps1" @(
  "-Fixture",
  "-ApplyLocal",
  "-Confirm", $confirm
)
if ($result.schema -ne "skybridge.managed_dev_pilot_manual_test.v1") { throw "Unexpected manual managed dev schema." }
if ($result.milestone -ne "M7: Managed Development PR Pilot") { throw "Unexpected M7 milestone." }
if ([int]$result.files_changed -ne 2) { throw "Expected two simulated changed files." }
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-True $result.held_for_human_review "held_for_human_review"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-managed-dev-pilot-fixture"
