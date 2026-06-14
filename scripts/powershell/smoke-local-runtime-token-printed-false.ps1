. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "safe-summary")
Assert-TokenPrintedFalse $summary
Complete-Smoke "local-runtime-token-printed-false"
