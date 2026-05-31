[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "requires-apply" -Json:$Json
exit $LASTEXITCODE
