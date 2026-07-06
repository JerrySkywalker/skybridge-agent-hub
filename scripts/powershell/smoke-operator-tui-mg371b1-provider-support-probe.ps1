$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b1RealProviderImplementation -Scenario "support-probe" -Reset

Assert-True $result.report.real_provider_path_implemented "real_provider_path_implemented"
Assert-True $result.report.real_provider_disabled_by_default "real_provider_disabled_by_default"
Assert-True $result.report.real_provider_requires_explicit_flag "real_provider_requires_explicit_flag"
Assert-True $result.report.real_provider_requires_exact_authorization "real_provider_requires_exact_authorization"
Assert-True $result.report.support_probe_passed "support_probe_passed"
Assert-False $result.report.real_provider_called "real_provider_called"
Assert-False $result.report.real_provider_mutation_executed "real_provider_mutation_executed"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b1-provider-support-probe"
