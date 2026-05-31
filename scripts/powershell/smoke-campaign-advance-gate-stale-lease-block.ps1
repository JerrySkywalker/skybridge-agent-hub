[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-gate-stale-lease-block" -Json:$Json
exit $LASTEXITCODE
