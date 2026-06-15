. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-rehearsal")
$command = @($result.commands | Where-Object { $_.command_id -eq "launcher-status" })[0]
if (-not $command -or $command.exit_code -ne 0) { throw "Extracted launcher status failed." }
Assert-NoUnsafeText ($command | ConvertTo-Json -Depth 20)
Assert-TokenPrintedFalse $command
Complete-Smoke "smoke-clean-room-extracted-launcher-status"
