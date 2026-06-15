. "$PSScriptRoot\smoke-productization-common.ps1"
$status = Invoke-JsonScript "skybridge-session-supervisor.ps1" @("-Command", "status")
if ($status.schema -ne "skybridge.session_supervisor_status.v1") { throw "schema mismatch" }
Assert-False $status.execution_enabled "execution_enabled"
Assert-False $status.queue_apply_enabled "queue_apply_enabled"
Assert-TokenPrintedFalse $status
Complete-Smoke "session-supervisor-status"
