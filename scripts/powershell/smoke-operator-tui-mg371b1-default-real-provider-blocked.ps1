$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b1RealProviderImplementation -Scenario "default-block" -Reset

Assert-True $result.default_block.blocked "default block"
if (@($result.report.blockers | ForEach-Object { [string]$_ }) -notcontains "real_mutation_disabled_by_default") {
  throw "Expected real_mutation_disabled_by_default blocker."
}
Assert-False $result.report.real_provider_called "real_provider_called"
Assert-False $result.report.real_mutation_enabled "real_mutation_enabled"
Assert-OperatorTuiMg371b1NoRealPr -Report $result.report -Support $result.support -Safety $result.safety
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b1-default-real-provider-blocked"
