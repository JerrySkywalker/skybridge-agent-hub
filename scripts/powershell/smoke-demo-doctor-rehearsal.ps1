. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "demo-doctor-rehearsal")
Assert-TokenPrintedFalse $report
Assert-TokenPrintedFalse $report.result
Assert-False $report.result.starts_codex_worker "starts_codex_worker"
Assert-False $report.result.runs_queue_apply "runs_queue_apply"
Assert-FileExists ".agent/tmp/local-launcher/demo-doctor-rehearsal-report.json"
Complete-Smoke "demo-doctor-rehearsal"
