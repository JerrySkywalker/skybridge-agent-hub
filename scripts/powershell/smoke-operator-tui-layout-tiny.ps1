. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiLayoutSmoke `
  -Name "operator-tui-layout-tiny" `
  -Scenario "tiny" `
  -Reset

Assert-True $result.report.tiny_layout_available "tiny_layout_available"
Assert-True $result.report.terminal_too_small_message_available "terminal_too_small_message_available"
if ($result.tiny_snapshot -notmatch "terminal too small") { throw "Tiny snapshot missing terminal-too-small message." }
if ($result.tiny_snapshot -notmatch "minimum recommended size") { throw "Tiny snapshot missing minimum-size message." }

Complete-Smoke "operator-tui-layout-tiny"
