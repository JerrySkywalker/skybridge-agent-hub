$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
Remove-Item -LiteralPath (Join-Path $root ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-ProviderId", "hermes_deepseek", "-Question", "command: powershell Get-ChildItem") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "run-next-hermes-preview")
Assert-False $result.output_executed "output_executed"
Assert-False $result.command_executed "command_executed"
Assert-False $result.workunit_created "workunit_created"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claim_created "task_claim_created"
Assert-False $result.task_pr_created "task_pr_created"
Assert-False $result.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-manual-task-hermes-output-not-executed] ok"
