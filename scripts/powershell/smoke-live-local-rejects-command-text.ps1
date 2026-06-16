$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$check = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "route-check", "-Route", "/metadata", "-Origin", "http://127.0.0.1:5173", "-Payload", "shell=echo fixture")
if ($check.accepted -ne $false) { throw "Command text was accepted." }
if (@($check.reasons) -notcontains "command_text_forbidden") { throw "Command text rejection reason missing." }
Assert-False $check.arbitrary_command_route_present "arbitrary_command_route_present"
Assert-False $check.execution_enabled "execution_enabled"
Assert-False $check.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-live-local-rejects-command-text] ok"
