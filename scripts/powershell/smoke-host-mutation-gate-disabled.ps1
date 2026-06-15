[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-host-mutation-gate.ps1" @("-Command", "gate")
if ($r.gate -ne "disabled") { throw "host mutation gate should be disabled." }
Assert-False $r.host_mutation_allowed "host_mutation_allowed"
Assert-False $r.permissions.registry_write_allowed "registry_write_allowed"
Write-Host "[smoke-host-mutation-gate-disabled] ok"
