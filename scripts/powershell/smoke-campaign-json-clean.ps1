[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "json-clean" -Json:$Json
exit $LASTEXITCODE
