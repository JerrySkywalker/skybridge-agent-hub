[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "campaign-gate-warnings-do-not-block" -Json:$Json
exit $LASTEXITCODE
