. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiManualReliabilitySmoke `
  -Name "operator-tui-manual-reliability-timeout-guidance" `
  -Scenario "timeout-guidance" `
  -Reset

if ([int]$result.timeout.manual_timeout_ms -lt 120000) {
  throw "manual_timeout_ms should be at least 120000."
}
Assert-True $result.timeout.timeout_enforced "timeout_enforced"
Assert-True $result.timeout.manual_timeout_guidance_visible "manual_timeout_guidance_visible"
Assert-True $result.timeout.smoke_remains_bounded "smoke_remains_bounded"
Assert-True $result.timeout.no_unbounded_wait "no_unbounded_wait"
Assert-False $result.timeout.token_printed "token_printed"

Complete-Smoke "operator-tui-manual-reliability-timeout-guidance"
