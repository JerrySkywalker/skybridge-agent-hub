$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$report = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "report")
Assert-False $report.summary.task_created "task_created"
Assert-False $report.summary.task_claim_created "task_claim_created"
Assert-False $report.summary.task_pr_created "task_pr_created"
Write-Host "[smoke-manual-task-no-task-pr-created] ok"
