. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "status")
if ($result.schema -ne "skybridge.launcher_route.v1") { throw "route schema mismatch" }
if ($result.result.schema -ne "skybridge.repo_local_launcher.v1") { throw "launcher schema mismatch" }
Assert-False $result.accepts_arbitrary_shell "accepts_arbitrary_shell"
Assert-False $result.starts_codex_worker "starts_codex_worker"
Assert-False $result.runs_workunit_apply "runs_workunit_apply"
Assert-False $result.claims_task "claims_task"
Assert-False $result.runs_queue_apply "runs_queue_apply"
Assert-TokenPrintedFalse $result
Complete-Smoke "repo-local-launcher-contract"
