$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$check = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "route-check", "-Route", "/metadata", "-Origin", "https://example.invalid")
if ($check.schema -ne "skybridge.live_local_route_check.v1") { throw "Live-local route check schema mismatch." }
if ($check.accepted -ne $false) { throw "Remote origin was accepted." }
if (@($check.reasons) -notcontains "origin_not_loopback") { throw "Remote origin rejection reason missing." }
Assert-False $check.execution_enabled "execution_enabled"
Assert-False $check.worker_execution_started "worker_execution_started"
Assert-False $check.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-live-local-rejects-remote-origin] ok"
