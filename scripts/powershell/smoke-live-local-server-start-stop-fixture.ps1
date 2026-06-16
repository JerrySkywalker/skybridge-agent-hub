$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$started = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "start-fixture")
if ($started.schema -ne "skybridge.live_local_server.v1") { throw "Live-local start schema mismatch." }
if ($started.status -ne "running") { throw "Live-local fixture did not start." }
if (-not (Get-Process -Id ([int]$started.pid) -ErrorAction SilentlyContinue)) { throw "Live-local fixture process missing." }

$stopped = Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "stop-fixture")
if ($stopped.status -ne "stopped") { throw "Live-local fixture did not stop." }
Assert-False $stopped.background_process_left "background_process_left"
if (Get-Process -Id ([int]$started.pid) -ErrorAction SilentlyContinue) { throw "Live-local fixture process still running." }
Write-Host "[smoke-live-local-server-start-stop-fixture] ok"
