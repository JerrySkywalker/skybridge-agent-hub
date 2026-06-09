. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$plan = Invoke-WorkerSchedulerJson "route-plan"
if ($plan.schema -ne "skybridge.workunit_route_plan.v1") { throw "Unexpected route plan schema." }
if (@($plan.selected_routes).Count -lt 1) { throw "Expected at least one selected route." }
if ($plan.task_claimed -or $plan.lease_created -or $plan.task_executed -or $plan.pr_created) { throw "Route plan must not mutate." }
Write-SmokeResult "worker-scheduler-route-plan"
