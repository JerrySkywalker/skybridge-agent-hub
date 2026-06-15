. "$PSScriptRoot\smoke-productization-common.ps1"
$null = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start", "-Apply", "-Profile", "full-local-preview", "-Bounded", "-Fixture")
$status = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "stop")
if ($status.status -ne "stopped") { throw "Expected stopped." }
Assert-False $status.background_process_left_running "background_process_left_running"
Assert-TokenPrintedFalse $status
Complete-Smoke "local-session-stop-fixture"
