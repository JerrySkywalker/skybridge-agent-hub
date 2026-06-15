[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-release-candidate-artifact.ps1" @("-Command", "verify")
if ($r.status -ne "passed") { throw "release artifact validation blocked." }
Assert-Truthy $r.forbidden_paths_absent "forbidden_paths_absent"
Assert-Truthy $r.checksum_present "checksum_present"
Write-Host "[smoke-release-artifact-validation] ok"
