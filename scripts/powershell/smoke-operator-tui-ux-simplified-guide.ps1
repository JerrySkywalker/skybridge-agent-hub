. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiUxYoloSmoke `
  -Name "operator-tui-ux-simplified-guide" `
  -Scenario "simplified-guide" `
  -Reset

Assert-True $result.report.simplified_guide_available "simplified_guide_available"
Assert-True $result.report.simplified_guide_default_for_manual_dry_run "simplified_guide_default_for_manual_dry_run"
foreach ($needle in @("Current step", "Next action", "Command status", "Safe to continue", "Expected result")) {
  if ($result.snapshot -notmatch [regex]::Escape($needle)) { throw "Simplified guide missing: $needle" }
}
foreach ($oldPanel in @("Pipeline Timeline", "Current Object", "Action Menu", "Safety Footer")) {
  if ($result.snapshot -match [regex]::Escape($oldPanel)) { throw "Simplified guide should not show old full panel: $oldPanel" }
}
Assert-False $result.report.token_printed "token_printed"

Complete-Smoke "operator-tui-ux-simplified-guide"
