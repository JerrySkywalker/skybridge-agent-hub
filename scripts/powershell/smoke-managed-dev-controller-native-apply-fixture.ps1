. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-fixture",
  "-Fixture",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr",
  "-Confirm", $confirm
)

Assert-False $result.preview_only "preview_only"
Assert-True $result.apply_confirmed "apply_confirmed"
Assert-True $result.branch_created "branch_created"
Assert-True $result.local_validations_run "local_validations_run"
Assert-True $result.local_validations_passed "local_validations_passed"
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-controller-native-apply-fixture"
