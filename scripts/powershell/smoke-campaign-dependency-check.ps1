[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "dependency-check" -Json:$Json
exit $LASTEXITCODE
