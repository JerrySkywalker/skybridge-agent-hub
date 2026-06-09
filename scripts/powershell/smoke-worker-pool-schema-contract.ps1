. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$schema = Invoke-WorkerSchedulerJson "schema"
foreach ($required in @("skybridge.worker_profile.v1", "skybridge.worker_pool.v1", "skybridge.worker_availability.v1", "skybridge.worker_capability_match.v1", "skybridge.worker_score.v1", "skybridge.scheduling_preview.v1", "skybridge.repo_parallelism_policy.v1", "skybridge.workunit_route_plan.v1", "skybridge.multi_worker_readiness.v1")) {
  if (@($schema.schemas) -notcontains $required) { throw "Missing schema $required" }
}
Write-SmokeResult "worker-pool-schema-contract"
