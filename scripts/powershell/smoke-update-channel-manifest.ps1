[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-channel-manifest.ps1" @("-Command", "manifest")
if (@($r.channels).Count -lt 4) { throw "expected four channels." }
Assert-False $r.network_update_allowed "network_update_allowed"
Assert-False $r.manual_upload_allowed "manual_upload_allowed"
Write-Host "[smoke-update-channel-manifest] ok"
