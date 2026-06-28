. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"

$gitMissing = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-local",
  "-Local",
  "-FixtureGitMissing",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr",
  "-Confirm", $confirm
)
if (-not (@($gitMissing.blockers) -contains "git_unavailable")) { throw "Expected git_unavailable blocker." }
Assert-False $gitMissing.branch_created "branch_created"

$ghMissing = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "create-draft-pr",
  "-Local",
  "-FixtureGhMissing",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr",
  "-Confirm", "I_UNDERSTAND_CREATE_ONE_DRAFT_PR_FOR_HUMAN_REVIEW_ONLY_NO_AUTO_MERGE"
)
if (-not (@($ghMissing.blockers) -contains "gh_unavailable")) { throw "Expected gh_unavailable blocker." }
Assert-False $ghMissing.draft_pr_created "draft_pr_created"

$repoDirty = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-local",
  "-Local",
  "-FixtureRepoNotClean",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr",
  "-Confirm", $confirm
)
if (-not (@($repoDirty.blockers) -contains "repo_not_clean")) { throw "Expected repo_not_clean blocker." }
Assert-False $repoDirty.branch_created "branch_created"

$branchExists = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-local",
  "-Local",
  "-FixtureBranchExists",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr",
  "-Confirm", $confirm
)
if (-not (@($branchExists.blockers) -contains "branch_exists")) { throw "Expected branch_exists blocker." }
Assert-False $branchExists.branch_created "branch_created"

foreach ($result in @($gitMissing, $ghMissing, $repoDirty, $branchExists)) {
  Assert-False $result.manual_fallback_used "manual_fallback_used"
  Assert-False $result.worker_loop_started "worker_loop_started"
  Assert-TokenPrintedFalse $result
}

Complete-Smoke "managed-dev-controller-native-blocker-classification"
