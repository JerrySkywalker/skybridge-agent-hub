. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$preview = Invoke-WorkerSchedulerJson "preview"
if ($preview.task_claimed -ne $false -or $preview.route_plan.task_claimed -ne $false) { throw "Scheduler preview must not claim tasks." }
Write-SmokeResult "worker-scheduler-preview-no-claim"
