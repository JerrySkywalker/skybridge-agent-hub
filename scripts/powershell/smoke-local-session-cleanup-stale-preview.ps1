. "$PSScriptRoot\smoke-productization-common.ps1"
$cleanup = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "cleanup")
if ($cleanup.schema -ne "skybridge.local_session_cleanup_preview.v1") { throw "schema mismatch" }
Assert-True $cleanup.preview_only "preview_only"
Assert-False $cleanup.kills_arbitrary_processes "kills_arbitrary_processes"
Assert-TokenPrintedFalse $cleanup
Complete-Smoke "local-session-cleanup-stale-preview"
