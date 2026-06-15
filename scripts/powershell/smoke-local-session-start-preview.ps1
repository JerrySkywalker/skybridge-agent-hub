. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start")
if ($plan.schema -ne "skybridge.local_session_start_plan.v1") { throw "schema mismatch" }
Assert-True $plan.preview_only "preview_only"
Assert-False $plan.starts_codex_worker "starts_codex_worker"
Assert-False $plan.runs_workunit_apply "runs_workunit_apply"
Assert-False $plan.claims_task "claims_task"
Assert-False $plan.queue_apply_enabled "queue_apply_enabled"
Assert-TokenPrintedFalse $plan
Complete-Smoke "local-session-start-preview"
