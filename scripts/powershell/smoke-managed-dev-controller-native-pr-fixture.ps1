. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "create-pr-preview",
  "-Fixture",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr"
)

Assert-True $result.preview_only "preview_only"
Assert-True $result.draft_pr_requested "draft_pr_requested"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-controller-native-pr-fixture"
