. "$PSScriptRoot\smoke-productization-common.ps1"
$cleanup = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "cleanup-stale-session")
if ($cleanup.schema -ne "skybridge.local_runtime_cleanup_report.v1") { throw "schema mismatch" }
Assert-False $cleanup.background_process_left_running "background_process_left_running"
Assert-False $cleanup.raw_log_persisted "raw_log_persisted"
Assert-TokenPrintedFalse $cleanup
Complete-Smoke "local-runtime-cleanup-stale"
