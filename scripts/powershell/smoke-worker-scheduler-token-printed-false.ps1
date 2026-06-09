. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
foreach ($command in @("schema", "pool", "readiness", "preview", "route-plan", "safe-summary", "fixture-workers", "fixture-workunits")) {
  $null = Invoke-WorkerSchedulerJson $command
}
Write-SmokeResult "worker-scheduler-token-printed-false"
