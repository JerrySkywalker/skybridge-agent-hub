[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "hermes-gate-schema" -Json:$Json
exit $LASTEXITCODE
