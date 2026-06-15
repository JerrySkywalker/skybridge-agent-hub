. "$PSScriptRoot\smoke-productization-common.ps1"
$items = @(
  (Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "report")),
  (Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "extract-smoke")),
  (Invoke-JsonScript "skybridge-manual-install-preview.ps1" @("-Command", "report")),
  (Invoke-JsonScript "skybridge-manual-uninstall-preview.ps1" @("-Command", "report"))
)
foreach ($item in $items) { Assert-TokenPrintedFalse $item }
Complete-Smoke "portable-package-253-256-token-printed-false"
