. "$PSScriptRoot\smoke-productization-common.ps1"
$status = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "status")
Assert-TokenPrintedFalse $status
if ($status.schema -ne "skybridge.portable_package.v1") { throw "Unexpected schema." }
Complete-Smoke "portable-package-builder-contract"
