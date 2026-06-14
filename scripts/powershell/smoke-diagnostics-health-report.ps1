. "$PSScriptRoot\smoke-productization-common.ps1"
$index = Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "report")
Assert-True $index.ok "diagnostics report index"
Assert-FileExists " .agent/tmp/diagnostics/health-report.json".Trim()
Assert-FileExists " .agent/tmp/product-readiness/product-readiness-report.json".Trim()
Complete-Smoke "diagnostics-health-report"
