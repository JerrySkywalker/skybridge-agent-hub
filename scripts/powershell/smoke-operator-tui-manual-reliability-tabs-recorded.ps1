. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiManualReliabilitySmoke `
  -Name "operator-tui-manual-reliability-tabs-recorded" `
  -Scenario "tabs-recorded" `
  -Reset

Assert-True $result.report.layout_modes_recorded "layout_modes_recorded"
Assert-True $result.report.tabs_visited_recorded "tabs_visited_recorded"
Assert-True $result.tab_history.help_opened "help_opened"
Assert-True $result.tab_history.actions_tab_visited "actions_tab_visited"
Assert-True $result.tab_history.runtime_tab_visited "runtime_tab_visited"
Assert-True $result.tab_history.safety_tab_visited "safety_tab_visited"
Assert-True $result.tab_history.confirmation_dialog_seen "confirmation_dialog_seen"
Assert-True $result.tab_history.reason_dialog_seen "reason_dialog_seen"
Assert-False $result.tab_history.token_printed "token_printed"

Complete-Smoke "operator-tui-manual-reliability-tabs-recorded"
