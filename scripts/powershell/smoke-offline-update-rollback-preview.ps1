[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$u = Invoke-SmokeJson "skybridge-channel-manifest.ps1" @("-Command", "offline-update-plan")
$r = Invoke-SmokeJson "skybridge-channel-manifest.ps1" @("-Command", "rollback-plan")
Assert-False $u.network_update_performed "network_update_performed"
Assert-False $u.host_mutation_performed "host_mutation_performed"
Assert-False $r.external_writes_performed "external_writes_performed"
Write-Host "[smoke-offline-update-rollback-preview] ok"
