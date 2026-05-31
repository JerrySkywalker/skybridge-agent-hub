[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "campaign-gate-final-decision-advance" -Json:$Json
exit $LASTEXITCODE
