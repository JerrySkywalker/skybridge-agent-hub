. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$preview = Invoke-WorkerSchedulerJson "preview"
if ($preview.lease_created -ne $false -or $preview.route_plan.lease_created -ne $false) { throw "Scheduler preview must not create leases." }
Write-SmokeResult "worker-scheduler-preview-no-lease"
