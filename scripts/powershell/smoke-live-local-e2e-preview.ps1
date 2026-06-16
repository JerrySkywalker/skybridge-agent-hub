$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "e2e-preview")
if ($report.schema -ne "skybridge.live_local_e2e_report.v1") { throw "Live-local E2E schema mismatch." }
if ($report.status -ne "passed") { throw "Live-local E2E did not pass." }
Assert-Truthy $report.remote_origin_rejected "remote_origin_rejected"
Assert-Truthy $report.command_text_rejected "command_text_rejected"
Assert-False $report.background_process_left "background_process_left"
Assert-False $report.worker_execution_started "worker_execution_started"
Assert-False $report.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-live-local-e2e-preview] ok"
