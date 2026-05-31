[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "hermes-gate-parse" -Json:$Json
exit $LASTEXITCODE
