. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiLayoutSmoke `
  -Name "operator-tui-layout-tabs" `
  -Scenario "tabs" `
  -Reset

Assert-True $result.report.tab_model_available "tab_model_available"
$tabs = @($result.report.tabs | ForEach-Object { [string]$_ })
foreach ($tab in @("Overview", "Pipeline", "Candidate", "Single-step", "Actions", "Runtime", "Safety", "Artifacts")) {
  if ($tabs -notcontains $tab) { throw "Missing tab: $tab" }
}
if ($result.full_snapshot -notmatch "Help") { throw "Tabs smoke should expose help surface." }
if ($result.full_snapshot -notmatch "Tab or ]") { throw "Help surface missing tab navigation keys." }

Complete-Smoke "operator-tui-layout-tabs"
