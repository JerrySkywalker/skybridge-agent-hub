. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInputUxSmoke `
  -Name "operator-tui-input-reason-sanitization" `
  -Scenario "reason-sanitization" `
  -Reset

Assert-True $result.reason.sensitive_marker_input_used "sensitive_marker_input_used"
Assert-True $result.reason.sanitization_changed "sanitization_changed"
if ([string]$result.reason.sanitized_reason_preview -ne "redacted_reason") {
  throw "Expected sanitized reason preview to be redacted_reason."
}
Assert-False $result.reason.raw_reason_persisted "raw_reason_persisted"
Assert-True $result.report.sanitized_reason_preview_available "sanitized_reason_preview_available"

Complete-Smoke "operator-tui-input-reason-sanitization"
