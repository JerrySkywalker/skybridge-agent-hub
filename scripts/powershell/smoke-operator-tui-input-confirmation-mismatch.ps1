. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInputUxSmoke `
  -Name "operator-tui-input-confirmation-mismatch" `
  -Scenario "confirmation-mismatch" `
  -Reset

Assert-True $result.mismatch.exact_confirmation_mismatch "exact_confirmation_mismatch"
Assert-True $result.mismatch.mismatch_feedback_visible "mismatch_feedback_visible"
Assert-True $result.mismatch.rejected_without_dispatch "rejected_without_dispatch"
Assert-True $result.report.retry_or_cancel_available "retry_or_cancel_available"

Complete-Smoke "operator-tui-input-confirmation-mismatch"
