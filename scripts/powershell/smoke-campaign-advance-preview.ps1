[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "advance-preview" -Json:$Json
exit $LASTEXITCODE
