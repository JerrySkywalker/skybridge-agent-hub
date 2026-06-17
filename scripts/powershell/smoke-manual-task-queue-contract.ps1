$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$summary = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "safe-summary")
Assert-Truthy $summary.ok "ok"
Assert-False $summary.hermes_live_call_enabled "hermes_live_call_enabled"
Assert-False $summary.worker_execution_started "worker_execution_started"
Assert-False $summary.workunit_created "workunit_created"
Assert-False $summary.task_created "task_created"
Assert-False $summary.task_pr_created "task_pr_created"
Assert-False $summary.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-manual-task-queue-contract] ok"
