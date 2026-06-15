. "$PSScriptRoot\smoke-productization-common.ps1"
$verification = Invoke-JsonScript "skybridge-portable-bundle.ps1" @("-Command", "verify")
Assert-TokenPrintedFalse $verification
Assert-True $verification.ok "verification ok"
Assert-False $verification.host_mutation_allowed "host_mutation_allowed"
Complete-Smoke "portable-bundle-verification"
