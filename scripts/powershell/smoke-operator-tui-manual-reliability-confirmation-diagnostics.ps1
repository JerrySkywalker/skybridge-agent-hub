. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiManualReliabilitySmoke `
  -Name "operator-tui-manual-reliability-confirmation-diagnostics" `
  -Scenario "confirmation-diagnostics" `
  -Reset

Assert-True $result.report.confirmation_diagnostics_available "confirmation_diagnostics_available"
Assert-True $result.report.expected_confirmation_length_recorded "expected_confirmation_length_recorded"
Assert-True $result.report.actual_confirmation_length_recorded "actual_confirmation_length_recorded"
Assert-True $result.report.first_mismatch_index_recorded "first_mismatch_index_recorded"
Assert-True $result.report.hidden_character_detection_available "hidden_character_detection_available"
Assert-True $result.report.confirmation_retry_guidance_visible "confirmation_retry_guidance_visible"
Assert-False $result.diagnostics.raw_input_persisted "raw_input_persisted"
Assert-False $result.report.token_printed "token_printed"

Complete-Smoke "operator-tui-manual-reliability-confirmation-diagnostics"
