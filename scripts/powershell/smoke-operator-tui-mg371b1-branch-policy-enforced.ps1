$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b1RealProviderImplementation -Scenario "branch-invalid" -Reset

Assert-True $result.branch_block.blocked "branch policy block"
Assert-False $result.branch_block.branch_policy_passed "branch_policy_passed"
if (@($result.report.blockers | ForEach-Object { [string]$_ }) -notcontains "branch_policy_failed") {
  throw "Expected branch_policy_failed blocker."
}
Assert-False $result.report.real_provider_called "real_provider_called"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b1-branch-policy-enforced"
