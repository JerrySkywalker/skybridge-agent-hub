. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-local-soak.ps1" @("-Command", "report")
if ($result.status -ne "passed") { throw "Fixture soak failed." }
Assert-False $result.starts_codex_worker "starts_codex_worker"
Assert-False $result.runs_workunit_apply "runs_workunit_apply"
Assert-False $result.runs_queue_apply "runs_queue_apply"
Assert-False $result.background_process_left_running "background_process_left_running"
Assert-False $result.raw_logs_persisted "raw_logs_persisted"
Assert-FileExists ".agent/tmp/local-session/fixture-soak-report.json"
Assert-TokenPrintedFalse $result
Complete-Smoke "smoke-local-fixture-soak"
