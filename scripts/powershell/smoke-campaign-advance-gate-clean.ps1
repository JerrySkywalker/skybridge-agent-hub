[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-gate-clean" -Json:$Json
exit $LASTEXITCODE
