$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b0CapabilityStaging -Scenario "no-real-pr" -Reset

Assert-OperatorTuiMg371b0NoRealPr `
  -Report $result.report `
  -Provider $result.provider `
  -Safety $result.safety
Assert-False $result.report.git_push_called "git_push_called"
Assert-False $result.report.gh_pr_create_called "gh_pr_create_called"
Assert-False $result.report.github_api_called "github_api_called"
Assert-False $result.provider.git_push_called "provider git_push_called"
Assert-False $result.provider.gh_pr_create_called "provider gh_pr_create_called"
Assert-False $result.provider.github_api_called "provider github_api_called"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b0-no-real-pr"
