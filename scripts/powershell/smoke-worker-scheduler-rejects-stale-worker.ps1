. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$plan = Invoke-WorkerSchedulerJson "route-plan" "stale"
if (-not (@($plan.rejected_workers).rejected_reasons -match "worker_stale")) { throw "Expected stale worker rejection." }
Write-SmokeResult "worker-scheduler-rejects-stale-worker"
