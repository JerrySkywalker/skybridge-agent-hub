[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$r = Invoke-SmokeJson "skybridge-release-walkthrough.ps1" @("-Command", "report")
Assert-Truthy $r.next_safe_action "next_safe_action"
Write-Host "[smoke-release-walkthrough] ok"
