. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_RUN_ONE_CAMPAIGN_DRIVEN_MANAGED_DEV_ACTION_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "run-fixture-e2e",
  "-Fixture",
  "-Confirm", $confirm
)

Assert-False $result.preview_only "preview_only"
Assert-True $result.apply_confirmed "apply_confirmed"
if ($result.appended_step_id -ne "managed-dev-campaign-step-362-fixture") { throw "Expected fixture appended step." }
if ($result.bounded_loop_selected_action -ne "managed_dev_draft_pr") { throw "Expected managed_dev_draft_pr action." }
Assert-True $result.bounded_loop_action_performed "bounded_loop_action_performed"
if (@($result.changed_files).Count -ne 1) { throw "Expected one simulated changed file." }
if (@($result.changed_files)[0] -ne "docs/orchestrator/CAMPAIGN_DRIVEN_MANAGED_DEV_MG362.md") { throw "Unexpected changed file." }
Assert-False $result.draft_pr_created "draft_pr_created"
if ($result.draft_pr_ci_status -ne "success") { throw "Expected success CI." }
Assert-True $result.held_for_human_review "held_for_human_review"
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-fixture-e2e"
