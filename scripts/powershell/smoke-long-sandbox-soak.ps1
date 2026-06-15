[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-long-soak.ps1" @("-Command", "sandbox-soak", "-CiSmoke", "-Cycles", "1")
if ($r.status -ne "passed") { throw "long sandbox soak failed." }
Assert-False $r.background_process_left "background_process_left"
Assert-False $r.raw_logs_persisted "raw_logs_persisted"
Write-Host "[smoke-long-sandbox-soak] ok"
