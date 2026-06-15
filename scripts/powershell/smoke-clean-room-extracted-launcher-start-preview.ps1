. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-rehearsal")
$command = @($result.commands | Where-Object { $_.command_id -eq "launcher-start-preview" })[0]
if (-not $command -or $command.exit_code -ne 0) { throw "Extracted launcher start-preview failed." }
Assert-False $command.starts_codex_worker "starts_codex_worker"
Assert-False $command.runs_workunit_apply "runs_workunit_apply"
Assert-False $command.runs_queue_apply "runs_queue_apply"
Assert-TokenPrintedFalse $command
Complete-Smoke "smoke-clean-room-extracted-launcher-start-preview"
