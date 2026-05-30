[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "status-output" -Json:$Json
exit $LASTEXITCODE
