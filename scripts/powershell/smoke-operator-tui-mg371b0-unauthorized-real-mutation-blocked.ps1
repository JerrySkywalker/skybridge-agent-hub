$ErrorActionPreference = "Stop"
. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiMg371b0CapabilityStaging `
  -Scenario "unauthorized-real-mutation-blocked" `
  -Reset `
  -RequestRealProvider

Assert-False $result.report.real_mutation_enabled "real_mutation_enabled"
Assert-False $result.report.real_mutation_authorized "real_mutation_authorized"
Assert-False $result.report.future_authorization_phrase_used_for_real_mutation "future_authorization_phrase_used_for_real_mutation"
Assert-False $result.report.real_provider_called "real_provider_called"
Assert-False $result.provider.real_provider_called "provider real_provider_called"
Assert-True $result.provider.real_provider_requested "provider real_provider_requested"
Assert-True $result.provider.real_provider_blocked "provider real_provider_blocked"
Assert-True $result.authorization.authorization_phrase_matched_for_future_flow "authorization_phrase_matched_for_future_flow"
Assert-False $result.authorization.real_mutation_authorized "authorization real_mutation_authorized"
Assert-False $result.authorization.phrase_used_for_real_mutation "authorization phrase_used_for_real_mutation"
Assert-TokenPrintedFalse $result.report

Complete-Smoke "operator-tui-mg371b0-unauthorized-real-mutation-blocked"
