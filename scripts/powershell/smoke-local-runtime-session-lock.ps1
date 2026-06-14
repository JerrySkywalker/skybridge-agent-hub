. "$PSScriptRoot\smoke-productization-common.ps1"
$session = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "start-local-session")
Assert-True $session.bounded "bounded"
Assert-True $session.stop_supported "stop_supported"
Assert-False $session.raw_log_persisted "raw_log_persisted"
$lock = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "lock-check")
Assert-False $lock.unsafe_component_detected "unsafe_component_detected"
Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "stop-local-session") | Out-Null
Complete-Smoke "local-runtime-session-lock"
