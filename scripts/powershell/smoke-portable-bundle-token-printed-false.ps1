. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-portable-bundle.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $report
Assert-NoUnsafeText (Get-Content -Raw (Join-Path $RepoRoot ".agent/tmp/portable-bundle/portable-bundle-manifest.json"))
Assert-NoUnsafeText (Get-Content -Raw (Join-Path $RepoRoot ".agent/tmp/portable-bundle/portable-bundle-report.json"))
Complete-Smoke "portable-bundle-token-printed-false"
