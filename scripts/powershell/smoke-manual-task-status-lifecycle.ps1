$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$queue = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "list")
foreach ($state in @("queued", "running", "succeeded", "failed", "blocked", "cancelled")) {
  if (@($queue.state_machine) -notcontains $state) { throw "Missing lifecycle state: $state" }
}
$status = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "status")
if ($status.schema -ne "skybridge.manual_task_queue.v1") { throw "Status schema mismatch." }
Assert-False $status.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-manual-task-status-lifecycle] ok"
