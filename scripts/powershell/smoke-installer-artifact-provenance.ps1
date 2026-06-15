[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-installer-promotion.ps1" @("-Command", "artifact-provenance")
Assert-Truthy $r.package_sha256 "package_sha256"
Assert-False $r.manual_upload_allowed "manual_upload_allowed"
Assert-False $r.github_release_manual_creation_allowed "github_release_manual_creation_allowed"
Assert-False $r.host_mutation_allowed "host_mutation_allowed"
Write-Host "[smoke-installer-artifact-provenance] ok"
