$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b1RealProviderImplementation -Scenario "allowlist-invalid" -Reset

Assert-True $result.allowlist_block.blocked "allowlist block"
Assert-False $result.allowlist_block.docs_only_allowlist_passed "docs_only_allowlist_passed"
if (@($result.allowlist_block.blocked_files | ForEach-Object { [string]$_ }) -notcontains "apps/operator-tui/src/main.rs") {
  throw "Expected app code to be blocked by MG371B1 allowlist."
}
if (@($result.report.blockers | ForEach-Object { [string]$_ }) -notcontains "docs_only_allowlist_failed") {
  throw "Expected docs_only_allowlist_failed blocker."
}
Assert-False $result.report.real_provider_called "real_provider_called"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b1-allowlist-enforced"
