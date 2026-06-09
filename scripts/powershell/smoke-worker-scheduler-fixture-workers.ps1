. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$pool = Invoke-WorkerSchedulerJson "pool"
if ($pool.schema -ne "skybridge.worker_pool.v1" -or @($pool.workers).Count -lt 3) { throw "Expected fixture worker pool." }
foreach ($worker in @($pool.workers)) {
  if ($worker.can_claim_tasks -ne $false -or $worker.can_execute_tasks -ne $false) { throw "Fixture worker must not claim or execute." }
}
Write-SmokeResult "worker-scheduler-fixture-workers"
