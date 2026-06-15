[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-release-walkthrough.ps1" @("-Command", "acceptance-v4")
Assert-Truthy $r.installer_promotion_gate "installer_promotion_gate"
Assert-Truthy $r.release_artifact_manifest "release_artifact_manifest"
Assert-Truthy $r.host_mutation_gate "host_mutation_gate"
Write-Host "[smoke-operator-acceptance-v4-report] ok status=$($r.status)"
