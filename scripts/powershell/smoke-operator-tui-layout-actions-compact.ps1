. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiLayoutSmoke `
  -Name "operator-tui-layout-actions-compact" `
  -Scenario "actions-compact" `
  -Reset

Assert-True $result.report.action_menu_compact_available "action_menu_compact_available"
if ($result.report.active_tab -ne "Actions") { throw "Expected Actions tab for compact action smoke." }
foreach ($needle in @("r Refresh", "g Generate candidate fixture", "q Quit")) {
  if ($result.compact_snapshot -notmatch [regex]::Escape($needle)) { throw "Compact actions snapshot missing: $needle" }
}

Complete-Smoke "operator-tui-layout-actions-compact"
