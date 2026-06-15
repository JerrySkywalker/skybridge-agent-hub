. "$PSScriptRoot\smoke-productization-common.ps1"
$reports = @(
  (Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-report")),
  (Invoke-JsonScript "skybridge-artifact-integrity.ps1" @("-Command", "report")),
  (Invoke-JsonScript "skybridge-local-soak.ps1" @("-Command", "report")),
  (Invoke-JsonScript "skybridge-operator-acceptance.ps1" @("-Command", "report"))
)
foreach ($report in $reports) {
  Assert-TokenPrintedFalse $report
  Assert-NoUnsafeText ($report | ConvertTo-Json -Depth 50)
}
Complete-Smoke "smoke-clean-room-257-260-token-printed-false"
