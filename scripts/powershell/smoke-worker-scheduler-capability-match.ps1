. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$plan = Invoke-WorkerSchedulerJson "route-plan" "capability-mismatch"
if (-not (@($plan.rejected_workers).rejected_reasons -match "worker_capability_mismatch")) { throw "Expected capability mismatch rejection." }
Write-SmokeResult "worker-scheduler-capability-match"
