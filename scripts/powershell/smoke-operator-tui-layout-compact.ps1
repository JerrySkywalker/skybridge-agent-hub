. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiLayoutSmoke `
  -Name "operator-tui-layout-compact" `
  -Scenario "compact" `
  -Reset

Assert-True $result.report.compact_layout_available "compact_layout_available"
if ($result.compact_snapshot -notmatch "mode=compact") { throw "Compact snapshot did not render compact marker." }
if ($result.compact_snapshot -notmatch "current tab only") { throw "Compact snapshot missing current-tab-only hint." }

Complete-Smoke "operator-tui-layout-compact"
