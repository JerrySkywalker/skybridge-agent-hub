. "$PSScriptRoot\smoke-productization-common.ps1"
$status = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start", "-Apply", "-Profile", "full-local-preview", "-Bounded", "-Fixture")
if ($status.schema -ne "skybridge.local_session.v1") { throw "schema mismatch" }
if ($status.status -ne "fixture_completed") { throw "Expected fixture_completed." }
Assert-False $status.lifecycle.background_process_left_running "background_process_left_running"
Assert-False $status.token_printed "token_printed"
Complete-Smoke "local-session-start-apply-bounded-fixture"
