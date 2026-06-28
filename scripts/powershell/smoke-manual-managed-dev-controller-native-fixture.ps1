. "$PSScriptRoot\smoke-productization-common.ps1"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-managed-dev-pr-pilot.ps1") `
  -Fixture `
  -ApplyLocal `
  -BranchName "codex/mg360-controller-native-managed-dev-pilot-pr" `
  -Confirm "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY" `
  -Json | ConvertFrom-Json

if ($result.schema -ne "skybridge.managed_dev_pilot_manual_test.v1") { throw "Unexpected manual managed-dev controller-native schema." }
Assert-True $result.result.branch_created "branch_created"
Assert-False $result.result.manual_fallback_used "manual_fallback_used"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-managed-dev-controller-native-fixture"
