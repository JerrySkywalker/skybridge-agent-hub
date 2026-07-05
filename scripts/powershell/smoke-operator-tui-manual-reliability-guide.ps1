. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiManualReliabilitySmoke `
  -Name "operator-tui-manual-reliability-guide" `
  -Scenario "guide" `
  -Reset

Assert-True $result.guide.dry_run_guide_available "dry_run_guide_available"
Assert-True $result.guide.guide_does_not_auto_execute "guide_does_not_auto_execute"
Assert-True $result.guide.wait_guidance_visible "wait_guidance_visible"
Assert-True $result.guide.required_confirmation_visible "required_confirmation_visible"
Assert-True $result.guide.reason_text_suggestions_visible "reason_text_suggestions_visible"
if (@($result.guide.steps).Count -ne 11) { throw "Expected 11 guide steps." }
Assert-False $result.guide.token_printed "token_printed"

Complete-Smoke "operator-tui-manual-reliability-guide"
