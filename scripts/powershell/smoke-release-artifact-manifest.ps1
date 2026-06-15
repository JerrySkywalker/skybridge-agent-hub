[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-release-candidate-artifact.ps1" @("-Command", "manifest")
Assert-Truthy $r.sha256 "sha256"
Assert-False $r.manual_github_release_created "manual_github_release_created"
Assert-False $r.manual_upload_performed "manual_upload_performed"
Assert-False $r.install_performed "install_performed"
Assert-False $r.network_update_performed "network_update_performed"
Write-Host "[smoke-release-artifact-manifest] ok"
