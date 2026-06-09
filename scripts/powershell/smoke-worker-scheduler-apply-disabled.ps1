. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$preview = Invoke-WorkerSchedulerJson "preview"
if ($preview.apply_available -ne $false) { throw "Scheduler apply must remain disabled." }
Write-SmokeResult "worker-scheduler-apply-disabled"
