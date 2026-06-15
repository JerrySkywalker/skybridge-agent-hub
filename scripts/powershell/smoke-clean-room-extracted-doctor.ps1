. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-rehearsal")
$command = @($result.commands | Where-Object { $_.command_id -eq "doctor-check" })[0]
if (-not $command -or $command.exit_code -ne 0) { throw "Extracted doctor check failed." }
if ($result.validation.doctor_status -ne "passed") { throw "Doctor validation not passed." }
Assert-TokenPrintedFalse $command
Complete-Smoke "smoke-clean-room-extracted-doctor"
