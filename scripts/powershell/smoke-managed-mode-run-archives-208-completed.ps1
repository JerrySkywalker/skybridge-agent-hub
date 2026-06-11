. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$archive = Invoke-ManagedModeRunJson "archive"
if ($archive.schema -ne "skybridge.managed_mode_completed_workunit_archive.v1") { throw "Unexpected archive schema." }
if ($archive.run_id -ne "managed-mode-pilot-208" -or $archive.state -ne "completed") { throw "208 must be archived as completed." }
if ($archive.pr_url -notmatch "/pull/140$" -or $archive.pr_state -ne "merged") { throw "208 archive must reference merged PR #140." }
Assert-ManagedModeRunSafeJson $archive
Write-ManagedModeRunSmokeResult "managed-mode-run-archives-208-completed"
