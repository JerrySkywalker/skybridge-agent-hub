. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-local-productization-rc.ps1" @("-Command", "report")
if ($report.schema -ne "skybridge.local_productization_rc_report.v1") { throw "schema mismatch" }
if ($report.rc_version -ne "v1.1.0-local-productization-rc") { throw "rc version mismatch" }
Assert-FileExists ".agent/tmp/product-readiness/local-productization-rc-report.json"
Assert-FileExists ".agent/tmp/product-readiness/local-productization-rc-report.md"
Assert-TokenPrintedFalse $report
Complete-Smoke "local-productization-rc-report"
