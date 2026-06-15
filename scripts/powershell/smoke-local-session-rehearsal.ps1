. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "rehearsal")
Assert-TokenPrintedFalse $report
Assert-False $report.starts_codex_worker "starts_codex_worker"
Assert-False $report.runs_workunit_apply "runs_workunit_apply"
Assert-False $report.leaves_background_process "leaves_background_process"
Assert-FileExists ".agent/tmp/local-session/local-session-rehearsal-report.json"
Complete-Smoke "local-session-rehearsal"
