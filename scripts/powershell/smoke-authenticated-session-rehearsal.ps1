$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-authenticated-session-rehearsal.ps1" @("-Command", "report")
if ($report.schema -ne "skybridge.authenticated_session_rehearsal.v1") { throw "Authenticated rehearsal schema mismatch." }
if ($report.status -ne "passed") { throw "Authenticated rehearsal did not pass." }
Assert-False $report.raw_token_persisted "raw_token_persisted"
Assert-False $report.auth_header_persisted "auth_header_persisted"
Assert-False $report.raw_logs_persisted "raw_logs_persisted"
Assert-False $report.worker_execution_started "worker_execution_started"
Assert-False $report.workunit_apply_enabled "workunit_apply_enabled"
Assert-False $report.queue_apply_enabled "queue_apply_enabled"
Assert-False $report.remote_execution_enabled "remote_execution_enabled"
Assert-False $report.arbitrary_command_enabled "arbitrary_command_enabled"
Assert-False $report.host_mutation_performed "host_mutation_performed"
Assert-False $report.background_process_left "background_process_left"
if ($report.doctor.unsafe_payloads_rejected -ne $true) { throw "Unsafe rehearsal payloads were not fully rejected." }

Write-Host "[smoke-authenticated-session-rehearsal] ok"
