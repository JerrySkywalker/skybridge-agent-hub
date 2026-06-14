. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-local-launch.ps1" @("-Command", "safe-summary")
Assert-False $summary.execution_enabled "execution_enabled"
Assert-False $summary.queue_apply_enabled "queue_apply_enabled"
Assert-False $summary.remote_execution_enabled "remote_execution_enabled"
Assert-False $summary.arbitrary_command_enabled "arbitrary_command_enabled"
Assert-TokenPrintedFalse $summary
Complete-Smoke "local-launch-execution-disabled"
