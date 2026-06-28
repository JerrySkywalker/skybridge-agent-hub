. "$PSScriptRoot\smoke-productization-common.ps1"

$beforeBranch = (git branch --show-current).Trim()
$beforeStatus = (git status --short | Out-String).Trim()
$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "preview",
  "-Fixture"
)
$afterBranch = (git branch --show-current).Trim()
$afterStatus = (git status --short | Out-String).Trim()

if ($beforeBranch -ne $afterBranch) { throw "Preview changed current branch." }
if ($beforeStatus -ne $afterStatus) { throw "Preview changed git status." }
Assert-True $result.preview_only "preview_only"
Assert-False $result.branch_created "branch_created"
Assert-False $result.draft_pr_created "draft_pr_created"
Assert-False $result.merge_performed "merge_performed"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-pilot-preview"
