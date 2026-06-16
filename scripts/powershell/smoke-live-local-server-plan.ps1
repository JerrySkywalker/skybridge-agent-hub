$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$plan = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "plan")
if ($plan.schema -ne "skybridge.live_local_server.v1") { throw "Live-local plan schema mismatch." }
if ($plan.status -ne "planned") { throw "Live-local plan status mismatch." }
Assert-Truthy $plan.loopback_only "loopback_only"
Assert-Truthy $plan.bounded_fixture_server_only "bounded_fixture_server_only"
Assert-False $plan.worker_execution_started "worker_execution_started"
Assert-False $plan.workunit_apply_enabled "workunit_apply_enabled"
Assert-False $plan.task_claim_enabled "task_claim_enabled"
Assert-False $plan.queue_apply_enabled "queue_apply_enabled"
Assert-False $plan.arbitrary_command_route_present "arbitrary_command_route_present"
Write-Host "[smoke-live-local-server-plan] ok"
