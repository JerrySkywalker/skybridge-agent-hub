$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
Remove-Item -LiteralPath (Join-Path $root ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
$result = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-Question", "What is the next safe manual task?")
if ($result.schema -ne "skybridge.manual_task_audit.v1") { throw "Manual task audit schema mismatch." }
if ($result.task.schema -ne "skybridge.manual_task.v1") { throw "Manual task schema mismatch." }
if ($result.task.status -ne "queued") { throw "Manual task was not queued." }
if ([string]::IsNullOrWhiteSpace($result.task.input_preview)) { throw "Missing input preview." }
Write-Host "[smoke-manual-task-add-question] ok"
