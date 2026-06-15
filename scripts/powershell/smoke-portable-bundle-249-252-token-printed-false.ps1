. "$PSScriptRoot\smoke-productization-common.ps1"
$items = @(
  (Invoke-JsonScript "skybridge-portable-bundle.ps1" @("-Command", "report")),
  (Invoke-JsonScript "skybridge-stop-hook-diagnostics.ps1" @("-Command", "report")),
  (Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "rehearsal")),
  (Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "demo-doctor-rehearsal"))
)
foreach ($item in $items) { Assert-TokenPrintedFalse $item }
Complete-Smoke "portable-bundle-249-252-token-printed-false"
