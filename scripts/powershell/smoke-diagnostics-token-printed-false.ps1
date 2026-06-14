. "$PSScriptRoot\smoke-productization-common.ps1"
$health = Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "health")
Assert-TokenPrintedFalse $health
Complete-Smoke "diagnostics-token-printed-false"
