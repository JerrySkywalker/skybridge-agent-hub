[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "gate-json-clean" -Json:$Json
exit $LASTEXITCODE
