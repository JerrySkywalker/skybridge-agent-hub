[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-installer-safety-interlock.ps1" @("-Command", "gate")
Assert-False $r.real_install_allowed "real_install_allowed"
Assert-False $r.network_update_allowed "network_update_allowed"
Assert-False $r.manual_upload_allowed "manual_upload_allowed"
Assert-False $r.manual_github_release_creation_allowed "manual_github_release_creation_allowed"
Write-Host "[smoke-installer-safety-interlock] ok"
