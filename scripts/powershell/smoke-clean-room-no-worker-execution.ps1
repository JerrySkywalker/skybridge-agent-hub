. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-rehearsal")
Assert-True $result.validation.no_worker_execution "no_worker_execution"
foreach ($command in @($result.commands)) {
  Assert-False $command.starts_codex_worker "command.starts_codex_worker"
  Assert-False $command.claims_task "command.claims_task"
}
Complete-Smoke "smoke-clean-room-no-worker-execution"
