. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiLayoutSmoke `
  -Name "operator-tui-layout-full" `
  -Scenario "full" `
  -Reset

Assert-True $result.report.full_layout_available "full_layout_available"
if ($result.full_snapshot -notmatch "layout=full") { throw "Full snapshot did not render full layout marker." }
if ($result.report.active_tab -ne "Overview") { throw "Expected Overview tab for full layout smoke." }

Complete-Smoke "operator-tui-layout-full"
