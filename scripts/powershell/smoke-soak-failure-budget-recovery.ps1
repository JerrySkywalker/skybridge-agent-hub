[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-long-soak.ps1" @("-Command", "report", "-CiSmoke", "-Cycles", "1")
if ($r.status -ne "passed") { throw "soak recovery report failed." }
Assert-False $r.sandbox.background_process_left "background_process_left"
Assert-False $r.sandbox.raw_logs_persisted "raw_logs_persisted"
Write-Host "[smoke-soak-failure-budget-recovery] ok"
