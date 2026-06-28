. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-campaign.ps1" @(
  "-Command", "preview",
  "-Fixture"
)

Assert-True $result.preview_only "preview_only"
Assert-False $result.bounded_loop_action_performed "bounded_loop_action_performed"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-campaign-preview"
