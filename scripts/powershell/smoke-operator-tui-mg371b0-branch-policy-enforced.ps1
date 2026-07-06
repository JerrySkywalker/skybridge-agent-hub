$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$passing = Invoke-OperatorTuiMg371b0CapabilityStaging -Scenario "capability-staging" -Reset
Assert-True $passing.branch.branch_name_valid "passing branch_name_valid"
if ([string]$passing.branch.branch_name -notlike "tui/mg371b-docs-only-pr-*") {
  throw "Passing branch does not use MG371B pattern."
}
Assert-True $passing.branch.no_spaces "passing no_spaces"
Assert-True $passing.branch.no_shell_metacharacters "passing no_shell_metacharacters"
Assert-True $passing.branch.under_80_characters "passing under_80_characters"

$blocked = Invoke-OperatorTuiMg371b0CapabilityStaging -Scenario "branch-invalid" -Reset
Assert-False $blocked.branch.branch_name_valid "blocked branch_name_valid"
$blockers = @($blocked.branch.blockers | ForEach-Object { [string]$_ })
if ($blockers -notcontains "branch_name_must_not_contain_spaces") {
  throw "Expected invalid branch to block spaces."
}
Assert-False $blocked.provider.fake_provider_executed "blocked provider fake_provider_executed"
Assert-TokenPrintedFalse $blocked.report

Complete-Smoke "operator-tui-mg371b0-branch-policy-enforced"
