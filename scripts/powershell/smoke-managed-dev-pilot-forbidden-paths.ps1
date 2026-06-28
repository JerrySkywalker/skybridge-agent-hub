. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
$forbidden = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-fixture",
  "-Fixture",
  "-ChangeKind", "forbidden-path-fixture",
  "-Confirm", $confirm
)
if (-not (@($forbidden.blockers) -contains "forbidden_changed_file_path")) {
  throw "Expected forbidden_changed_file_path blocker."
}
Assert-False $forbidden.branch_created "branch_created"
Assert-False $forbidden.draft_pr_created "draft_pr_created"

$max = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-fixture",
  "-Fixture",
  "-MaxChangedFiles", "6",
  "-Confirm", $confirm
)
if (-not (@($max.blockers) -contains "max_changed_files_must_be_between_1_and_5")) {
  throw "Expected max changed files blocker."
}
Assert-False $max.branch_created "branch_created"
Assert-TokenPrintedFalse $forbidden
Assert-TokenPrintedFalse $max

Complete-Smoke "managed-dev-pilot-forbidden-paths"
