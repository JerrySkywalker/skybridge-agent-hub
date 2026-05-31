[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "campaign-gate-final-decision-hard-veto" -Json:$Json
exit $LASTEXITCODE
