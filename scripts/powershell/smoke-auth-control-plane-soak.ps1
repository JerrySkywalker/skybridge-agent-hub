$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-auth-soak.ps1" @("-Command", "report", "-Iterations", "5", "-MaxDurationSeconds", "240")
if ($report.schema -ne "skybridge.auth_soak_report.v1") { throw "Auth soak schema mismatch." }
if ($report.status -ne "passed") { throw "Auth soak did not pass." }
Assert-False $report.raw_token_persisted "raw_token_persisted"
Assert-False $report.auth_header_persisted "auth_header_persisted"
Assert-False $report.raw_logs_persisted "raw_logs_persisted"
Assert-False $report.worker_execution_started "worker_execution_started"
Assert-False $report.queue_apply_enabled "queue_apply_enabled"
Assert-False $report.host_mutation_performed "host_mutation_performed"
if ($report.fixture_auth_soak.iterations_completed -ne 5) { throw "Fixture auth soak iteration count mismatch." }
if ($report.control_plane_auth_soak.iterations_completed -ne 5) { throw "Control-plane auth soak iteration count mismatch." }

Write-Host "[smoke-auth-control-plane-soak] ok"
