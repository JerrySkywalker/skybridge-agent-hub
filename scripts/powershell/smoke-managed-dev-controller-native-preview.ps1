. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "preview",
  "-Fixture",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr"
)

Assert-True $result.preview_only "preview_only"
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-controller-native-preview"
