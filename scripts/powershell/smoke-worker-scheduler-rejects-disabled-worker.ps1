. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$plan = Invoke-WorkerSchedulerJson "route-plan" "disabled"
if (-not (@($plan.rejected_workers).rejected_reasons -match "worker_disabled")) { throw "Expected disabled worker rejection." }
Write-SmokeResult "worker-scheduler-rejects-disabled-worker"
