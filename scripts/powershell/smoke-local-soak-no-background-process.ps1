. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-local-soak.ps1" @("-Command", "safe-summary")
Assert-False $result.background_process_left_running "background_process_left_running"
Assert-False $result.raw_logs_persisted "raw_logs_persisted"
Assert-TokenPrintedFalse $result
Complete-Smoke "smoke-local-soak-no-background-process"
