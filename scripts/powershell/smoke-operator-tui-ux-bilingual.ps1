. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiUxYoloSmoke `
  -Name "operator-tui-ux-bilingual" `
  -Scenario "bilingual" `
  -Reset

$languages = @($result.report.available_languages | ForEach-Object { [string]$_ })
if ($languages -notcontains "zh-CN") { throw "zh-CN language missing." }
Assert-True $result.report.bilingual_ui_available "bilingual_ui_available"
Assert-True $result.report.language_toggle_available "language_toggle_available"
Assert-True $result.report.language_toggled "language_toggled"
Assert-True $result.report.zh_cn_translations_available "zh_cn_translations_available"
Assert-True $result.report.exact_confirmations_untranslated "exact_confirmations_untranslated"
foreach ($needle in @("当前步骤", "下一步", "需要确认", "安全状态")) {
  if ($result.zh_snapshot -notmatch [regex]::Escape($needle)) { throw "zh-CN snapshot missing: $needle" }
}
Assert-False $result.report.token_printed "token_printed"

Complete-Smoke "operator-tui-ux-bilingual"
