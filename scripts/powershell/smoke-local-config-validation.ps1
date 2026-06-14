. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-local-config.ps1" @("-Command", "report")
Assert-True $report.validation.ok "validation.ok"
Assert-True $report.redaction.ok "redaction.ok"
Assert-FileExists ".agent/tmp/product-readiness/local-config-validation-report.json"
Assert-TokenPrintedFalse $report
Complete-Smoke "local-config-validation"
