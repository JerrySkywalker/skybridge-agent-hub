$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
Remove-Item -LiteralPath (Join-Path $root ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-Question", "shell=echo should-not-run; whoami") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "run-next-mock")
Assert-False $result.output_executed "output_executed"
Assert-False $result.command_executed "command_executed"
if ($result.result_preview -notlike "*no_execution*") { throw "Command-like task was not classified as no-execution." }
Write-Host "[smoke-manual-task-does-not-execute-commands] ok"
