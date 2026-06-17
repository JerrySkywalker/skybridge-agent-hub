$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

Remove-Item -LiteralPath (Join-Path (Resolve-Path "$PSScriptRoot\..\..") ".agent\tmp\manual-task\manual-task-queue.json") -Force -ErrorAction SilentlyContinue
Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "add-question", "-ProviderId", "skybridge_server_hermes", "-Question", "command: powershell Get-ChildItem") | Out-Null
$result = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "run-next-skybridge-hermes")
Assert-False $result.output_executed "output_executed"
Assert-False $result.command_executed "command_executed"
Assert-False $result.remote_execution_enabled "remote_execution_enabled"
Assert-False $result.arbitrary_command_enabled "arbitrary_command_enabled"
Assert-False $result.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-manual-task-server-hermes-output-not-executed] ok"
