. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "start-preview")
if ($result.result.schema -ne "skybridge.local_session_start_plan.v1") { throw "start preview schema mismatch" }
Assert-True $result.result.preview_only "preview_only"
Assert-False $result.result.starts_codex_worker "starts_codex_worker"
Assert-False $result.result.runs_workunit_apply "runs_workunit_apply"
Assert-TokenPrintedFalse $result
Complete-Smoke "repo-local-launcher-start-preview"
