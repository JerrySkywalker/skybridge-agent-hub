[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "pack-validate" -Json:$Json
exit $LASTEXITCODE
