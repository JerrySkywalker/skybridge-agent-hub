$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b1RealProviderImplementation -Scenario "no-real-pr" -Reset

Assert-OperatorTuiMg371b1NoRealPr `
  -Report $result.report `
  -Support $result.support `
  -Safety $result.safety
Assert-False $result.report.git_push_called "git_push_called"
Assert-False $result.report.gh_pr_create_called "gh_pr_create_called"
Assert-False $result.report.github_api_called "github_api_called"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b1-no-real-pr"
