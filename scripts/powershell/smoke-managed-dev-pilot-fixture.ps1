. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-fixture",
  "-Fixture",
  "-Confirm", $confirm
)
Assert-False $result.preview_only "preview_only"
Assert-True $result.apply_confirmed "apply_confirmed"
Assert-True $result.branch_created "branch_created"
if ([int]$result.files_changed -ne 2) { throw "Expected two simulated changed files." }
foreach ($file in @($result.changed_files)) {
  if ($file -notmatch "^(docs/orchestrator/|scripts/powershell/smoke-managed-dev-)") {
    throw "Changed file outside managed-dev fixture allowed paths: $file"
  }
}
Assert-True $result.local_validations_run "local_validations_run"
Assert-True $result.local_validations_passed "local_validations_passed"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-True $result.held_for_human_review "held_for_human_review"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-pilot-fixture"
