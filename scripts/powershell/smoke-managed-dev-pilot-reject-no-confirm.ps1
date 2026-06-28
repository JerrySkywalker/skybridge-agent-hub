. "$PSScriptRoot\smoke-productization-common.ps1"

$beforeBranch = (git branch --show-current).Trim()
$beforeStatus = (git status --short | Out-String).Trim()
$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-local",
  "-Local",
  "-BranchName", "codex/mega-357-managed-dev-pr-pilot-test-no-confirm"
)
$afterBranch = (git branch --show-current).Trim()
$afterStatus = (git status --short | Out-String).Trim()

if ($beforeBranch -ne $afterBranch) { throw "Rejected local apply changed branch." }
if ($beforeStatus -ne $afterStatus) { throw "Rejected local apply changed git status." }
if (-not (@($result.blockers) -contains "missing_apply_confirmation")) {
  throw "Expected missing_apply_confirmation blocker."
}
Assert-False $result.apply_confirmed "apply_confirmed"
Assert-False $result.branch_created "branch_created"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-pilot-reject-no-confirm"
