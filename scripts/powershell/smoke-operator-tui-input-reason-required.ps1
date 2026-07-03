. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiInputUxSmoke `
  -Name "operator-tui-input-reason-required" `
  -Scenario "reason-required" `
  -Reset

Assert-True $result.reason.reason_required_enforced "reason_required_enforced"
Assert-True $result.report.reason_dialog_available "reason_dialog_available"
Assert-True $result.report.reason_required_enforced "report reason_required_enforced"

Complete-Smoke "operator-tui-input-reason-required"
