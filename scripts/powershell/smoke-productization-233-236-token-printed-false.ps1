. "$PSScriptRoot\smoke-productization-common.ps1"
$items = @()
$items += Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "safe-summary")
$items += Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "safe-summary")
$items += Invoke-JsonScript "skybridge-update-preview.ps1" @("-Command", "safe-summary")
$items += Invoke-JsonScript "skybridge-backup-restore-preview.ps1" @("-Command", "safe-summary")
foreach ($item in $items) { Assert-TokenPrintedFalse $item }
Complete-Smoke "productization-233-236-token-printed-false"
