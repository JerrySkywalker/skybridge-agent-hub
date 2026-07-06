$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b1RealProviderImplementation -Scenario "authorization-required" -Reset

Assert-True $result.authorization_block.blocked "authorization block"
Assert-False $result.authorization_block.authorization_phrase_matched "authorization_phrase_matched"
if (@($result.report.blockers | ForEach-Object { [string]$_ }) -notcontains "authorization_phrase_mismatch") {
  throw "Expected authorization_phrase_mismatch blocker."
}
Assert-False $result.authorization_block.authorization_phrase_used_for_real_mutation "authorization phrase used for real mutation"
Assert-False $result.report.real_provider_called "real_provider_called"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b1-authorization-required"
