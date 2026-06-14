. "$PSScriptRoot\smoke-productization-common.ps1"
$candidate = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "apply-candidate")
if ($candidate.schema -ne "skybridge.local_runtime_apply_candidate.v1") { throw "schema mismatch" }
Assert-True $candidate.bounded "bounded"
Assert-True $candidate.stop_supported "stop_supported"
Assert-False $candidate.starts_codex_worker "starts_codex_worker"
Assert-False $candidate.runs_workunit_apply "runs_workunit_apply"
Assert-False $candidate.queue_apply_enabled "queue_apply_enabled"
Assert-TokenPrintedFalse $candidate
Complete-Smoke "local-runtime-apply-candidate"
