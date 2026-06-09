. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$preview = Invoke-WorkerSchedulerJson "preview"
if ($preview.task_executed -ne $false -or $preview.route_plan.task_executed -ne $false -or $preview.pr_created -ne $false) { throw "Scheduler preview must not execute or create PRs." }
Write-SmokeResult "worker-scheduler-preview-no-execution"
