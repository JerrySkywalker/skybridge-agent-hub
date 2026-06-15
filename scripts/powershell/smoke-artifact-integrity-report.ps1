. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-artifact-integrity.ps1" @("-Command", "report")
Assert-True $result.clean_room_verified "clean_room_verified"
Assert-False $result.upload_allowed "upload_allowed"
Assert-False $result.install_allowed "install_allowed"
Assert-False $result.host_mutation_allowed "host_mutation_allowed"
Assert-FileExists ".agent/tmp/portable-package/artifact-integrity-report.json"
Assert-FileExists ".agent/tmp/portable-package/artifact-integrity-report.md"
Assert-TokenPrintedFalse $result
Complete-Smoke "smoke-artifact-integrity-report"
