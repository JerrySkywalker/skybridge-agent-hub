. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-rehearsal")
Assert-True $result.validation.no_queue_apply "no_queue_apply"
foreach ($command in @($result.commands)) {
  Assert-False $command.runs_queue_apply "command.runs_queue_apply"
}
Complete-Smoke "smoke-clean-room-no-queue-apply"
