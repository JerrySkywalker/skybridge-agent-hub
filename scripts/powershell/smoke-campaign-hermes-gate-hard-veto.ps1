[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "hermes-gate-hard-veto" -Json:$Json
exit $LASTEXITCODE
